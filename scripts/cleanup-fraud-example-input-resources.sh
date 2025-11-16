#!/bin/bash

# --- Function to check if a command was successful ---
# Used primarily by execute_cleanup_command to log status.
check_status() {
  local exit_code=$?
  if [ $exit_code -eq 0 ]; then
    echo "✅ SUCCESS: $1"
  else
    # Captures the full error output for the warning message
    # Note: For cleanup scripts, "resource not found" errors are often safe to ignore,
    # but we log the failure/warning for full transparency.
    local error_output=$(< /dev/stdin)
    echo "⚠️ WARNING: $1 failed, but continuing cleanup. Error detail: ${error_output}" >&2
  fi
}

# --- Function to execute a command and feed error output to check_status ---
execute_cleanup_command() {
  local command_desc="$1"
  shift
  # Executes the command, captures stderr (2>&1) to the 'output' variable,
  # then feeds output to check_status through stdin.
  local output
  output=$("$@" 2>&1)
  echo "${output}" | check_status "${command_desc}"
}

# --- Argument Validation ---
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <PROJECT_ID>"
  echo "Example: $0 my-gcp-project"
  exit 1
fi

# --- Configuration Variables ---
PROJECT_ID="$1"
TOPIC_ID="fraud-example-transactions"
SERVICE_ACCOUNT_ID="fraud-example"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
SUBSCRIPTION_ID="${TOPIC_ID}-sub"

# IAM Roles (Used to construct the IAM binding removal commands)
PUBSUB_SUBSCRIBER_ROLE="roles/pubsub.subscriber"
AIPLATFORM_USER_ROLE="roles/aiplatform.user"

echo "--- Starting Cleanup of Reasoning Engine Pipeline Resources in Project ${PROJECT_ID} ---"

## 1. Project Context

echo "1. Setting gcloud project to ${PROJECT_ID}..."
gcloud config set project "${PROJECT_ID}"
check_status "Set gcloud project configuration"

## 2. Resource Deletion (Subscriptions, Topic, Service Account)

# Deleting Subscription
echo "2. Deleting Pub/Sub Subscription: ${SUBSCRIPTION_ID}..."
# The --quiet flag suppresses confirmation prompts.
execute_cleanup_command "Pub/Sub Subscription ${SUBSCRIPTION_ID} deletion" \
  gcloud pubsub subscriptions delete "${SUBSCRIPTION_ID}" --quiet

# Deleting Topic
echo "3. Deleting Pub/Sub Topic: ${TOPIC_ID}..."
execute_cleanup_command "Pub/Sub Topic ${TOPIC_ID} deletion" \
  gcloud pubsub topics delete "${TOPIC_ID}" --quiet

## 3. IAM Binding Removal (Must happen before Service Account deletion)

echo "4. Removing IAM Bindings for Service Account: ${SERVICE_ACCOUNT_EMAIL}..."

# A. Remove AI Platform User Role
execute_cleanup_command "Remove AI Platform User role on project" \
  gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="${AIPLATFORM_USER_ROLE}"

# B. Remove Pub/Sub Subscriber Role
execute_cleanup_command "Remove Pub/Sub Subscriber role on project" \
  gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="${PUBSUB_SUBSCRIBER_ROLE}"

## 4. Delete Service Account

echo "5. Deleting Service Account: ${SERVICE_ACCOUNT_ID}..."
# The --quiet flag suppresses confirmation prompts.
execute_cleanup_command "Service Account ${SERVICE_ACCOUNT_EMAIL} deletion" \
  gcloud iam service-accounts delete "${SERVICE_ACCOUNT_EMAIL}" --quiet

echo "🎉 Cleanup complete. All resources and IAM bindings have been removed or did not exist."