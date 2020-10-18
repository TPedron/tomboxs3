#!/bin/sh
bundle

# NOTE: Set your AWS access keys here or leave commented out and set in ~/.aws/credentials
#       See: # https://docs.aws.amazon.com/sdk-for-ruby/v3/developer-guide/setup-config.html
# export AWS_ACCESS_KEY_ID=""
# export AWS_SECRET_ACCESS_KEY=""

export TOMBOXS3_BUCKET_NAME="tomboxs3"
export TOMBOXS3_REGION="ca-central-1" # canada
export TOMBOXS3_MAGIC_DIR_PATH="/Users/tompedron/Downloads/tomboxs3_magic_dir"
export DEBUG_LOGGING="FALSE"

ruby tomboxs3.rb