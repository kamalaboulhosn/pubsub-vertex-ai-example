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
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <PROJECT_ID> <REGION>"
  echo "Example: $0 my-gcp-project us-central1"
  exit 1
fi

PROJECT_ID="$1"
REGION="$2"
DATASET_ID="fraud_example"
TRANSACTIONS_TABLE="transactions"
CARDS_TABLE="compromised-cards"
BUCKET_NAME="fraud-example-staging-${PROJECT_ID}"
TRANSACTIONS_TOPIC="fraud-example-augmented-transactions"
CARDS_TOPIC="fraud-example-compromised-cards"
TRANSACTIONS_SUB="${TRANSACTIONS_TOPIC}-sub"
CARDS_SUB="${CARDS_TOPIC}-sub"
BIGQUERY_ROLE="roles/bigquery.dataEditor"
PUBSUB_PUBLISH_ROLE="roles/pubsub.publisher"

echo "--- Initializing GCP Resources (Idempotent) ---"
echo "Project ID: ${PROJECT_ID}"
echo "Region: ${REGION}"

## 1. Setup and Project Context

echo "1. Setting gcloud project to ${PROJECT_ID}..."
gcloud config set project "${PROJECT_ID}"
check_status "Set gcloud project configuration"

## 2. Get Project Number and P4SA Emails
echo "2. Fetching Project Number and P4SA emails..."
PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
PUBSUB_P4SA="service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com"
AIPLATFORM_P4SA="service-${PROJECT_NUMBER}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"
check_status "Fetched all P4SA emails"

## 3. BigQuery Resource Creation

echo "3. Creating BigQuery Dataset: ${DATASET_ID} in region ${REGION}..."
create_resource_idempotently \
  "BigQuery Dataset creation" \
  "already exists" \
  bq mk --dataset --location "${REGION}" "${PROJECT_ID}:${DATASET_ID}"

echo "4. Creating BigQuery Table: ${DATASET_ID}.${TRANSACTIONS_TABLE}..."
TRANSACTIONS_SCHEMA='[{"name": "credit_card_number", "type": "STRING", "mode": "NULLABLE"},{"name": "receiver", "type": "STRING", "mode": "NULLABLE"},{"name": "amount", "type": "FLOAT", "mode": "NULLABLE"},{"name": "ip_address", "type": "STRING", "mode": "NULLABLE"},{"name": "fraud_likelihood", "type": "FLOAT", "mode": "NULLABLE"},{"name": "fraud_reason", "type": "STRING", "mode": "NULLABLE"},{"name": "timestamp", "type": "DATETIME", "mode": "NULLABLE"}]'
SCHEMA_FILE_TX="/tmp/${TRANSACTIONS_TABLE}_schema.json"
echo "${TRANSACTIONS_SCHEMA}" > "${SCHEMA_FILE_TX}"
create_resource_idempotently \
  "BigQuery 'transactions' table creation" \
  "already exists" \
  bq mk --table "${PROJECT_ID}:${DATASET_ID}.${TRANSACTIONS_TABLE}" "${SCHEMA_FILE_TX}"
rm "${SCHEMA_FILE_TX}"

echo "5. Creating BigQuery Table: ${DATASET_ID}.${CARDS_TABLE}..."
CARDS_SCHEMA='[{"name": "credit_card_number", "type": "STRING", "mode": "NULLABLE"},{"name": "fraud_likelihood", "type": "NUMERIC", "mode": "NULLABLE"},{"name": "fraud_reason", "type": "STRING", "mode": "NULLABLE"},{"name": "timestamp", "type": "DATETIME", "mode": "NULLABLE"}]'
SCHEMA_FILE_CARDS="/tmp/${CARDS_TABLE}_schema.json"
echo "${CARDS_SCHEMA}" > "${SCHEMA_FILE_CARDS}"
create_resource_idempotently \
  "BigQuery 'compromisedcards' table creation" \
  "already exists" \
  bq mk --table "${PROJECT_ID}:${DATASET_ID}.${CARDS_TABLE}" "${SCHEMA_FILE_CARDS}"
rm "${SCHEMA_FILE_CARDS}"

## 4. Cloud Storage and Pub/Sub Topic Creation

echo "6. Creating Cloud Storage Bucket: gs://${BUCKET_NAME} in region ${REGION}..."
create_resource_idempotently \
  "Cloud Storage Bucket creation" \
  "Your previous request to create the named bucket succeeded and you already own it." \
  gcloud storage buckets create "gs://${BUCKET_NAME}" --project="${PROJECT_ID}" --location="${REGION}" --uniform-bucket-level-access

echo "7. Creating Pub/Sub Topic: ${TRANSACTIONS_TOPIC} and ${CARDS_TOPIC}..."
create_resource_idempotently \
  "Pub/Sub Topic ${TRANSACTIONS_TOPIC} creation" \
  "Resource already exists" \
  gcloud pubsub topics create "${TRANSACTIONS_TOPIC}"

create_resource_idempotently \
  "Pub/Sub Topic ${CARDS_TOPIC} creation" \
  "Resource already exists" \
  gcloud pubsub topics create "${CARDS_TOPIC}"

## 5. IAM Bindings

echo "8. Granting Pub/Sub P4SA (${PUBSUB_P4SA}) BigQuery Data Editor role to project ${PROJECT_ID}..."
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${PUBSUB_P4SA}" \
  --role="${BIGQUERY_ROLE}"
check_status "IAM Policy Binding for Pub/Sub to BigQuery"

echo "9. Granting AI Platform P4SA (${AIPLATFORM_P4SA}) Pub/Sub Publisher role to topics..."
# Granting Publisher role to the 'augmented-transactions' topic
gcloud pubsub topics add-iam-policy-binding "${TRANSACTIONS_TOPIC}" \
  --member="serviceAccount:${AIPLATFORM_P4SA}" \
  --role="${PUBSUB_PUBLISH_ROLE}"
check_status "IAM Binding for AI Platform to ${TRANSACTIONS_TOPIC}"

# Granting Publisher role to the 'compromised-cards' topic
gcloud pubsub topics add-iam-policy-binding "${CARDS_TOPIC}" \
  --member="serviceAccount:${AIPLATFORM_P4SA}" \
  --role="${PUBSUB_PUBLISH_ROLE}"
check_status "IAM Binding for AI Platform to ${CARDS_TOPIC}"

## 6. Pub/Sub Subscription Creation

echo "10. Creating Pub/Sub Subscription: ${TRANSACTIONS_SUB} for BigQuery table ${TRANSACTIONS_TABLE}..."
create_resource_idempotently \
  "Pub/Sub Subscription ${TRANSACTIONS_SUB} creation" \
  "Resource already exists" \
  gcloud pubsub subscriptions create "${TRANSACTIONS_SUB}" --topic="${TRANSACTIONS_TOPIC}" --bigquery-table="${PROJECT_ID}:${DATASET_ID}.${TRANSACTIONS_TABLE}" --use-table-schema

echo "11. Creating Pub/Sub Subscription: ${CARDS_SUB} for BigQuery table ${CARDS_TABLE}..."
create_resource_idempotently \
  "Pub/Sub Subscription ${CARDS_SUB} creation" \
  "Resource already exists" \
  gcloud pubsub subscriptions create "${CARDS_SUB}" --topic="${CARDS_TOPIC}" --bigquery-table="${PROJECT_ID}:${DATASET_ID}.${CARDS_TABLE}" --use-table-schema

echo "🎉 All required GCP resources have been initialized successfully!"