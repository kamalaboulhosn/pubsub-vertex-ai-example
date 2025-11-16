#!/bin/bash

# --- Function to check general status ---
check_status() {
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo "✅ SUCCESS: $1"
    else
        echo "❌ FAILURE (Exit Code: $exit_code): $1" >&2
        exit 1
    fi
}

# --- Function to handle 'already exists' errors specifically ---
create_resource_idempotently() {
    local command_desc="$1"
    shift
    local exists_message_part="$1"
    shift

    local command_array=("$@")

    local output
    output=$("${command_array[@]}" 2>&1)
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo "✅ SUCCESS: ${command_desc}"
    elif [[ "$output" =~ "$exists_message_part" ]]; then
        echo "⚠️ WARNING: ${command_desc} (Resource already exists, treating as success.)"
    else
        echo "❌ FAILURE (Exit Code: $exit_code): ${command_desc}" >&2
        echo "Error details: ${output}" >&2
        exit 1
    fi
}

# --- Argument Validation ---
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <PROJECT_ID> <REGION> <REASONING_ENGINE_ID>"
    echo "Example: $0 my-gcp-project us-central1 43210987654"
    exit 1
fi

# --- Configuration Variables ---
# These variables receive their values directly from the command line arguments
PROJECT_ID="$1"
REGION="$2"
REASONING_ENGINE_ID="$3"
TOPIC_ID="fraud-example-transactions"
SERVICE_ACCOUNT_ID="fraud-example"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
SUBSCRIPTION_ID="${TOPIC_ID}-sub"
ACK_DEADLINE=600 # 10 minutes

# --- Path Resolution for SMT File ---
# BASH_SOURCE[0] provides the path used to execute the script.
# This logic ensures the script can find the SMT file relative to the project structure,
# regardless of the Current Working Directory (CWD).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# Assuming the project root is the parent directory of the 'scripts' directory
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
SMT_FILE_NAME="fraud-example-smt.yml"
SMT_FILE_PATH="${PROJECT_ROOT}/smt/${SMT_FILE_NAME}"

# IAM Roles
PUBSUB_SUBSCRIBER_ROLE="roles/pubsub.subscriber"
AIPLATFORM_USER_ROLE="roles/aiplatform.user"

# Construct the dynamic push endpoint URL
PUSH_ENDPOINT_URL="https://${REGION}-aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/reasoningEngines/${REASONING_ENGINE_ID}:streamQuery"

echo "--- Initializing Reasoning Engine Pipeline Resources (Idempotent) ---"
echo "Project ID: ${PROJECT_ID}"
echo "Region: ${REGION}"
echo "Reasoning Engine ID: ${REASONING_ENGINE_ID}"
echo "Push Endpoint: ${PUSH_ENDPOINT_URL}"
echo "---"

## 1. Setup Project Context
echo "1. Setting gcloud project to ${PROJECT_ID}..."
gcloud config set project "${PROJECT_ID}"
check_status "Set gcloud project configuration"
echo "---"

## 2. Create Pub/Sub Topic
echo "2. Creating Pub/Sub Topic: ${TOPIC_ID}..."
create_resource_idempotently \
    "Pub/Sub Topic creation" \
    "Resource already exists" \
    gcloud pubsub topics create "${TOPIC_ID}"
echo "---"

## 3. Create Service Account
echo "3. Creating Service Account: ${SERVICE_ACCOUNT_ID} (${SERVICE_ACCOUNT_EMAIL})..."
create_resource_idempotently \
    "Service Account creation" \
    "already exists" \
    gcloud iam service-accounts create "${SERVICE_ACCOUNT_ID}" \
        --display-name="Fraud Example Service Account"

# NEW: Pause to allow IAM system to recognize the new service account
echo "Pausing for 10 seconds to allow service account propagation..."
sleep 10
echo "---"

## 4. Grant Pub/Sub Subscriber Role to SA (Required for push)
echo "4. Granting SA (${SERVICE_ACCOUNT_EMAIL}) Pub/Sub Subscriber Role..."
# Granting permission at the project level is sufficient for the service account to be used by the subscription
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="${PUBSUB_SUBSCRIBER_ROLE}"
check_status "IAM Policy Binding for Pub/Sub Subscriber Role"
echo "---"

## 5. Grant AI Platform User Role to SA (Required for API call)
echo "5. Granting SA (${SERVICE_ACCOUNT_EMAIL}) AI Platform User Role..."
# This role grants the SA permission to call the streamQuery endpoint
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="${AIPLATFORM_USER_ROLE}"
check_status "IAM Policy Binding for AI Platform User Role"
echo "---"


## 6. Create Pub/Sub Push Subscription
echo "6. Creating Pub/Sub Push Subscription: ${SUBSCRIPTION_ID}..."
# Use the calculated absolute path (SMT_FILE_PATH)
create_resource_idempotently \
    "Pub/Sub Push Subscription creation" \
    "Resource already exists" \
    gcloud pubsub subscriptions create "${SUBSCRIPTION_ID}" \
        --topic="${TOPIC_ID}" \
        --enable-message-ordering \
        --push-endpoint="${PUSH_ENDPOINT_URL}" \
        --push-auth-service-account="${SERVICE_ACCOUNT_EMAIL}" \
        --ack-deadline="${ACK_DEADLINE}" \
        --message-transforms-file="${SMT_FILE_PATH}" \
        --push-no-wrapper
echo "---"

echo "🎉 All required GCP resources for the Reasoning Engine pipeline have been initialized successfully!"