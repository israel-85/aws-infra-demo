import json
import boto3
import logging
import os
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
secretsmanager = boto3.client('secretsmanager')

def handler(event, context):
    """
    AWS Lambda function to handle secret rotation for application configuration.
    This is a basic rotation function that can be extended based on specific needs.
    """
    
    # Extract information from the event
    secret_arn = event.get('SecretId')
    token = event.get('ClientRequestToken')
    step = event.get('Step')
    
    logger.info(f"Starting rotation for secret: {secret_arn}, step: {step}")
    
    try:
        if step == "createSecret":
            create_secret(secret_arn, token)
        elif step == "setSecret":
            set_secret(secret_arn, token)
        elif step == "testSecret":
            test_secret(secret_arn, token)
        elif step == "finishSecret":
            finish_secret(secret_arn, token)
        else:
            logger.error(f"Invalid step: {step}")
            raise ValueError(f"Invalid step: {step}")
            
        logger.info(f"Successfully completed step: {step}")
        return {"statusCode": 200, "body": json.dumps("Success")}
        
    except Exception as e:
        logger.error(f"Error in step {step}: {str(e)}")
        raise e

def create_secret(secret_arn, token):
    """Create a new version of the secret with updated values."""
    try:
        # Get the current secret value
        current_secret = secretsmanager.get_secret_value(SecretId=secret_arn, VersionStage="AWSCURRENT")
        current_data = json.loads(current_secret['SecretString'])
        
        # Create new secret data (this is a simple example - customize based on your needs)
        new_data = current_data.copy()
        
        # For application config, we might update API keys, tokens, etc.
        # This is a placeholder - implement actual rotation logic based on your needs
        if 'apiVersion' in new_data:
            # Increment version or update timestamp
            import time
            new_data['lastRotated'] = int(time.time())
            new_data['rotationId'] = token[:8]  # Use part of token as rotation ID
        
        # Put the new secret version
        secretsmanager.put_secret_value(
            SecretId=secret_arn,
            ClientRequestToken=token,
            SecretString=json.dumps(new_data),
            VersionStages=['AWSPENDING']
        )
        
        logger.info("Successfully created new secret version")
        
    except ClientError as e:
        if e.response['Error']['Code'] == 'ResourceExistsException':
            logger.info("Secret version already exists")
        else:
            raise e

def set_secret(secret_arn, token):
    """Configure the service to use the new secret version."""
    # For application configuration secrets, this step might involve
    # updating external services or configurations
    # This is a placeholder implementation
    logger.info("Setting secret - no external configuration needed for app config")

def test_secret(secret_arn, token):
    """Test the new secret version to ensure it works."""
    try:
        # Get the pending secret version
        pending_secret = secretsmanager.get_secret_value(
            SecretId=secret_arn,
            VersionId=token,
            VersionStage="AWSPENDING"
        )
        
        # Parse and validate the secret
        secret_data = json.loads(pending_secret['SecretString'])
        
        # Perform basic validation
        if not isinstance(secret_data, dict):
            raise ValueError("Secret data must be a JSON object")
            
        # Add more specific validation based on your secret structure
        required_fields = ['apiVersion']
        for field in required_fields:
            if field not in secret_data:
                raise ValueError(f"Required field '{field}' missing from secret")
        
        logger.info("Secret validation passed")
        
    except Exception as e:
        logger.error(f"Secret validation failed: {str(e)}")
        raise e

def finish_secret(secret_arn, token):
    """Finalize the rotation by updating version stages."""
    try:
        # Move the AWSCURRENT stage to the new version
        secretsmanager.update_secret_version_stage(
            SecretId=secret_arn,
            VersionStage="AWSCURRENT",
            ClientRequestToken=token,
            RemoveFromVersionId=get_current_version_id(secret_arn)
        )
        
        logger.info("Successfully finished secret rotation")
        
    except Exception as e:
        logger.error(f"Failed to finish rotation: {str(e)}")
        raise e

def get_current_version_id(secret_arn):
    """Get the version ID of the current secret."""
    try:
        response = secretsmanager.describe_secret(SecretId=secret_arn)
        for version_id, stages in response['VersionIdsToStages'].items():
            if 'AWSCURRENT' in stages:
                return version_id
        raise ValueError("No current version found")
    except Exception as e:
        logger.error(f"Failed to get current version ID: {str(e)}")
        raise e