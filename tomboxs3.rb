require 'aws-sdk-s3'
require "json"
require 'fileutils'

BUCKET_NAME = ENV["TOMBOXS3_BUCKET_NAME"] || "bucket_name"
REGION  = ENV["TOMBOXS3_REGION"] || "region"
MANIFEST_PATH = ENV["TOMBOXS3_MANIFEST_PATH"] || "s3_manifest.json"
MAGIC_DIR_PATH = ENV["TOMBOXS3_MAGIC_DIR_PATH"] || ""

@local_items

execute()

########

def execute()
    init_manifest_file unless manifest.present?
    connect_to_bucket(REGION, BUCKET_NAME)
    validate_from_remote_bucket
end

def connect_to_bucket(region, bucket_name)
    @s3 = Aws::S3::Resource.new(region: region) #'us-west-2'
    @bucket = @s3.bucket(bucket_name) if @s3.present? # 'my-bucket'
end

def validate_from_remote_bucket()
    # Show only the first 50 items
    @bucket.objects.limit(50).each do |item|
    puts "Name:  #{item.key}"
    puts "URL:   #{item.presigned_url(:get)}"
    validate_against_local(item)
  end
end

def validate_against_local(item)
    manifest.
end

def download_item_from_remote(key)
    item = @bucket.object(key)
    ite.get(response_target: "#{MAGIC_DIR_PATH}/#{key}")
end

def manifest_item(key)
    manifest["items"].find {|item| item['key'] == key}
end

def manifest_items
    manifest["items"]
end

def manifest
    begin
        @manifest ||= JSON.load(File.open(MANIFEST_PATH))
    rescue => exception
        return nil
    end
end

def init_manifest_file
    FileUtils.cp("s3_manifest_template.json", MANIFEST_PATH)
    manifest
end
