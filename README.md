# Vertex AI Agent Engine Pub/Sub Example
Contains the code for a Vertex AI Agent Engine fraud agent fed data via Cloud Pub/Sub. The repository consists of four parts:

1. **fraud-agent**: A Python-based agent that runs on [Vertex AI Agent Engine](https://docs.cloud.google.com/agent-builder/agent-engine/overview), designed to evaluate credit card transactions for fraud. It includes a script to deploy the agent.
2. **data-generator**: A Java-based application that generates fake credit card transactions and publishes them to Pub/Sub.
3. **scripts**: A set of bash scripts to create and cleanup input and output resources for the agent including Pub/Sub topics and subscrptions and BigQuery tables.
4. **smt**: A Pub/Sub [single message transform](https://docs.cloud.google.com/pubsub/docs/smts/smts-overview) [user-defined function](https://docs.cloud.google.com/pubsub/docs/smts/udfs-overview) used with the subscription that sends messsages to the agent.

## Requirements

You need to have a Google Cloud project set up that is enabled for Pub/Sub, BigQuery, and Vertex AI Agent Engine. The project will be used for the rest of the steps and referred to as `PROJECT_ID`. For the agent, you need to have Python and pip installed. For the data generator, you need Java and Maven. For the scripts, you need [gcloud](https://docs.cloud.google.com/sdk/gcloud). You also need to choose a region for the deployment, e.g., us-central1. This region will be referred to as `REGION` for the rest of the instructions.

## Creete Output Resources

The first step is to create the resources used as outputs from the agent. After cloning the repository, run the following command from the top-level directory

```bash
scripts/fraund-agent-resources.sh <PROJECT_ID> <REGION>
```

## Deploy The Agent

From the `fraud-agent` directory, run the following. You might first want to create and activate a virtual environment:

```bash
python3 -m venv .venv
source .venv/bin/activate
```
Then you can install the requirements locally and deploy the agent:

```bash

pip install -r requirements.txt
python3 deploy.py <PROJECT_ID> <REGION>
```
The `STAGING_BUCKET` is the Cloud Storage bucket created in the output resources script. Once this step completes, you should see output like the following:

```
INFO: To use this AgentEngine in another session:
agent_engine = vertexai.agent_engines.get('projects/<PROJECT_NUMBER>/locations/<LOCATION>/reasoningEngines/<ENGINE_ID>')
INFO: agent_engine = vertexai.agent_engines.get('projects/<PROJECT_NUMBER>/locations/<LOCATION>/reasoningEngines/<ENGINE_ID>')
Remote agent created/updated successfully: Fraud Agent
```

Take note of the `ENGINE_ID`.

## Create Input Resources

To create the topic to publish messages to and the push subscription, run the following from the top-level directory of the repository:

```bash
scripts/create-fraud-example-output-resources.sh <PROJECT_ID> <REGION> <ENGINE_ID>
```

The `ENGINE_ID` is the one noted from the previous step.

You now have the entire pipeline up and running.

## Generating Data

The `data-generator` directory contains a Java application that generates fake credit card transactions. You can run it from that directory as follows:

```bash
mvn package
java -jar target/TransactionGenerator.jar <PROJECT_ID> <REGION>
```
## Cleanup

If you want to delete all of the resources you can run the following commands:

```bash
scripts/cleanup-fraud-example-input-resources.sh <PROJECT_ID> 
scripts/cleanup-fraud-example-ou-resources.sh <PROJECT_ID>
cd fraud-agent
python3 delete.py <PROJECT_ID> <REGION> <ENGINE_ID>
```

