#!/bin/bash

# --- Function to check if a command was successful ---
# Used primarily by execute_cleanup_command to log status.
check_status() {
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo "✅ SUCCESS: $1"
    else
        # Captures the full error output for the warning message
        local error_output=$(< /dev/stdin)
        echo "⚠️ WARNING: $1 failed, but continuing cleanup. Error detail: ${error_output}" >&2
    fi
}

# --- Function to execute a command and feed error output to check_status ---
execute_cleanup_command() {
    local command_desc="$1"
    shift
    # Executes the command, captures stderr to the 'output' variable,
    # then feeds output to check_status through stdin.
    local output
    output=$("$@" 2>&1)
    echo "${output}" | check_status "${command_desc}"
}

# --- Argument Validation (Updated to require only 1 argument) ---
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <PROJECT_ID>"
    echo "Example: $0 my-gcp-project"
    exit 1
fi

PROJECT_ID="$1"
# REGION="$2" has been removed, as it is unused for deletion.

# --- Configuration Variables (Synchronized with Setup Script) ---
DATASET_ID="fraud_example"
BUCKET_NAME="fraud-example-staging-${PROJECT_ID}"
TRANSACTIONS_TOPIC="fraud-example-augmented-transactions"
CARDS_TOPIC="fraud-example-compromised-cards"
TRANSACTIONS_SUB="${TRANSACTIONS_TOPIC}-sub"
CARDS_SUB="${CARDS_TOPIC}-sub"

# IAM Roles
BIGQUERY_ROLE="roles/bigquery.dataEditor"
PUBSUB_PUBLISH_ROLE="roles/pubsub.publisher"

echo "--- Starting Cleanup of GCP Resources in Project ${PROJECT_ID} ---"

## 1. Project Context and P4SA Derivation

echo "1. Setting gcloud project to ${PROJECT_ID}..."
gcloud config set project "${PROJECT_ID}"
check_status "Set gcloud project configuration"

echo "1.1 Fetching Project Number and P4SA emails..."
PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
PUBSUB_P4SA="service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com"
AIPLATFORM_P4SA="service-${PROJECT_NUMBER}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"
echo "   P4SA Pub/Sub: ${PUBSUB_P4SA}"
echo "   P4SA AI Platform: ${AIPLATFORM_P4SA}"

# Deleting Subscriptions
echo "2. Deleting Pub/Sub Subscription: ${TRANSACTIONS_SUB}..."
execute_cleanup_command "Pub/Sub Subscription ${TRANSACTIONS_SUB} deletion" gcloud pubsub subscriptions delete "${TRANSACTIONS_SUB}" --quiet

echo "3. Deleting Pub/Sub Subscription: ${CARDS_SUB}..."
execute_cleanup_command "Pub/Sub Subscription ${CARDS_SUB} deletion" gcloud pubsub subscriptions delete "${CARDS_SUB}" --quiet

## 2. IAM Binding Removal (Must happen before Topic deletion)

echo "4. Removing IAM Bindings..."

# A. Remove Pub/Sub Publisher Role from Augmented Topic (AIPLATFORM_P4SA)
execute_cleanup_command "Remove AIPLATFORM Publisher role on ${TRANSACTIONS_TOPIC}" \
    gcloud pubsub topics remove-iam-policy-binding "${TRANSACTIONS_TOPIC}" \
    --member="serviceAccount:${AIPLATFORM_P4SA}" \
    --role="${PUBSUB_PUBLISH_ROLE}"

# B. Remove Pub/Sub Publisher Role from Compromised Topic (AIPLATFORM_P4SA)
execute_cleanup_command "Remove AIPLATFORM Publisher role on ${CARDS_TOPIC}" \
    gcloud pubsub topics remove-iam-policy-binding "${CARDS_TOPIC}" \
    --member="serviceAccount:${AIPLATFORM_P4SA}" \
    --role="${PUBSUB_PUBLISH_ROLE}"

# C. Remove BigQuery Data Editor Role from Project (PUBSUB_P4SA)
execute_cleanup_command "Remove PUBSUB BigQuery Data Editor role" \
    gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${PUBSUB_P4SA}" \
    --role="${BIGQUERY_ROLE}"

## 3. Resource Deletion (Topics, Bucket, Dataset)

# Deleting Topics
echo "5. Deleting Pub/Sub Topic: ${TRANSACTIONS_TOPIC}..."
execute_cleanup_command "Pub/Sub Topic ${TRANSACTIONS_TOPIC} deletion" gcloud pubsub topics delete "${TRANSACTIONS_TOPIC}" --quiet

echo "6. Deleting Pub/Sub Topic: ${CARDS_TOPIC}..."
execute_cleanup_command "Pub/Sub Topic ${CARDS_TOPIC} deletion" gcloud pubsub topics delete "${CARDS_TOPIC}" --quiet

# Cloud Storage Cleanup
echo "7. Deleting Cloud Storage Bucket: gs://${BUCKET_NAME}..."
# Using --recursive (-r) and the global --quiet flag to suppress the confirmation prompt.
execute_cleanup_command "Cloud Storage Bucket ${BUCKET_NAME} deletion" gcloud --quiet storage rm --recursive "gs://${BUCKET_NAME}"

# BigQuery Cleanup
echo "8. Deleting BigQuery Dataset: ${DATASET_ID} (including tables)..."
# Using the -r (recursive) AND --force flags to ensure silent deletion of the dataset and its contents.
execute_cleanup_command "BigQuery Dataset ${DATASET_ID} deletion" bq rm --dataset -r --force "${PROJECT_ID}:${DATASET_ID}"

echo "🎉 Cleanup complete. All resources and IAM bindings have been removed or did not exist."