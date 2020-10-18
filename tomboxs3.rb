require 'aws-sdk-s3'
require "json"
require 'fileutils'
require 'listen'

BUCKET_NAME = ENV["TOMBOXS3_BUCKET_NAME"] # Required
REGION  = ENV["TOMBOXS3_REGION"] # Required
MAGIC_DIR_PATH = ENV["TOMBOXS3_MAGIC_DIR_PATH"] # Required
MANIFEST_FILE_NAME = ENV["MANIFEST_FILE_NAME"] || "s3_manifest.json" # Optional
MANIFEST_FILE_PATH = "#{MAGIC_DIR_PATH}/#{MANIFEST_FILE_NAME}".freeze
DEBUG_LOGGING = ENV["DEBUG_LOGGING"] || "FALSE" # Optional

class Tomboxs3

  def initialize(region, bucket_name)
    validate_env_vars
    connect_to_s3_bucket(region, bucket_name)
  end

  def validate_env_vars
    raise "ENV EXCEPTION - BUCKET_NAME" if BUCKET_NAME.nil?
    raise "ENV EXCEPTION - REGION" if REGION.nil?
    raise "ENV EXCEPTION - MAGIC_DIR_PATH" if MAGIC_DIR_PATH.nil?
  end

  def monitor
    listener = Listen.to(MAGIC_DIR_PATH) do
      pp "TOMBOXS3 SYNC START #{start = Time.now}"
      perform_sync
      pp "TOMBOXS3 SYNC COMPLETE #{finish = Time.now} - Total time: #{finish - start} sec."
    end

    listener.start
    listener.ignore /#{MANIFEST_FILE_NAME}/ # if we don't ignore this, we infinitely loop on the dir being changed
    pp "MONITOR DIR #{MAGIC_DIR_PATH}"
    sleep
  end

  def log(msg)
    pp msg unless DEBUG_LOGGING == "FALSE"
  end

  def perform_sync
    files_hash = determine_file_changes
    new_files = determine_new_files_in_local_dir

    log("New Files to upload")
    log(new_files)

    log("Files to update")
    log(files_hash[:files_to_update])

    log("Files to delete")
    log(files_hash[:files_to_delete])

    # SYNC S3
    log("S3 Calls Start")
    upload_new_files(new_files) if new_files.any?
    update_files(files_hash[:files_to_update]) if files_hash[:files_to_update].any?
    delete_files(files_hash[:files_to_delete]) if files_hash[:files_to_delete].any?
    log("S3 Calls End")

    # Update manifest
    log("Regenerate local manifest")
    regenerate_local_manifest(files_hash[:files_in_dir] + new_files)
  end

  def print_all_files_in_s3
    log("PRINT FILES IN S3 BUCKET")
    index = 1
    @bucket.objects.each do |item|
      s3obj = item.get
      log("#{index}:  #{item.key}")
      index+=1
    end
  end

  private

  ########## SYNC ##########
  def determine_file_changes
    files_in_dir = [] # NOTE: stores all files that exist locally
    existing_files = [] # NOTE: Stores all filenames that have been synced before (exist locally & in s3)
    files_to_update = [] # NOTE: Stores all filenames that exist locally & remotely with different md5 values
    # new_files = [] # NOTE: Stores all filenames that exist locally but not remotely
    files_to_delete = []
    
    idx = 1
    manifest_items.each do |manifest_hash|
      filename = manifest_hash["name"]

      local_file_data = find_file_local_dir(filename)

      if local_file_data[:file_found_local_dir]
        files_in_dir << filename
      else
        files_to_delete << filename
      end

      s3_data = find_file_in_s3_bucket(filename)

      if s3_data[:found_in_s3]
        s3_file = s3_data[:s3_file]
        s3obj = s3_data[:s3obj]
        existing_files << filename
        files_to_update << filename if file_updated?(manifest_hash["md5"], s3obj.metadata["md5"])
      else
        # IF NOT FOUND IN S3 BUT EXISTS IN MANIFEST THEN IT MUST HAVE BEEN DELETED ON S3
        # TODO: Implement local delete based on remote change
      end

      idx+=1
    end

    return {
      files_in_dir: files_in_dir,
      existing_files: existing_files,
      # new_files: new_files,
      files_to_update: files_to_update,
      files_to_delete: files_to_delete
    }
  end

  def determine_new_files_in_local_dir
    new_files = []

    Dir.foreach(MAGIC_DIR_PATH) do |filename|
      next if filename == '.' ||
              filename == '..' ||
              filename == MANIFEST_FILE_NAME ||
              filename.start_with?('.')

      manifest_file = manifest_item(filename)
      new_files << filename if manifest_file.nil?
    end

    new_files
  end

  def find_file_local_dir(filename)
    file = nil
    begin
      file = File.open("#{MAGIC_DIR_PATH}/#{filename}")
    rescue
      log("COULDNT FIND FILE LOCALLY")
    end

    {
      file: file,
      file_found_local_dir: !file.nil?
    }
  end

  def file_updated?(local_md5, remote_md5)
    log("Local md5  = #{local_md5}")
    log("Remote md5 = #{remote_md5}")
    local_md5  != remote_md5
  end

  ########## MANIFEST ##########
  def regenerate_local_manifest(files)
    json_array = []
    files.each do |curr_file|
      s3_item = @bucket.object(curr_file)
      json_array << {
        name: curr_file,
        md5: generate_md5_local_file(curr_file),
        paths: {
          local_full_path: "#{MAGIC_DIR_PATH}/#{curr_file}",
          local_relative_path: "/#{curr_file}",
        },
        s3_data: {
          s3_url: s3_item.presigned_url(:get),
          s3_bucket: s3_item.bucket_name,
          s3_etag: s3_item.etag,
          s3_last_modified: s3_item.last_modified,
          s3_size: s3_item.size,
          s3_storage_class: s3_item.storage_class
        }
      }
    end

    log("MANIFEST DATA")
    manifest_data = {
      most_recent_sync_time: Time.now,
      num_files: json_array.length,
      files: json_array
    }
    log(manifest_data)

    File.write(MANIFEST_FILE_PATH, JSON.pretty_generate(manifest_data)) #manifest_data.to_json)
  end

  def manifest_item(key)
    manifest_items.find {|item| item["name"] == key}
  end
 
  def manifest_items
    log("MANIFEST ITEMS")
    log(manifest)
    manifest["files"]
  end
 
  def manifest
    begin
      @manifest ||= JSON.load(File.open(MANIFEST_FILE_PATH))
    rescue => exception
      return nil
    end
  end

  ########## S3 ##########
  def connect_to_s3_bucket(region, bucket_name)
    @s3 = Aws::S3::Resource.new(
      # access_key_id: creds['access_key_id'],
      # secret_access_key: creds['secret_access_key'],
      region: region
    )

    @bucket = @s3.bucket(bucket_name) #if @s3.present? # 'my-bucket'
  end

  def find_file_in_s3_bucket(filename)
    curr_file = @bucket.object(filename)
    s3obj = curr_file.get if !curr_file.nil?

    {
      s3_file: curr_file,
      s3obj: s3obj,
      found_in_s3: !s3obj.nil?
    }
  end

  def upload_new_files(new_files)
    log("UPLOAD NEW")
    new_files.each do |file|
      log("-- Uploading new file #{file} to s3")
      upload_file(file)
    end
  end

  def update_files(files_to_update)
    log("UPDATE EXISTING")
    files_to_update.each do |file|
      log("-- Updating file #{file} on s3")
      upload_file(file)
    end
  end

  def upload_file(filename)
    log(filename)
    # Create the object to upload
    obj = @bucket.object(filename)

    # Metadata to add
    metadata = {
      "md5": generate_md5_local_file(filename)
    }

    # Upload it  
    log("UPLOAD")
    obj.upload_file("#{MAGIC_DIR_PATH}/#{filename}", metadata: metadata)
  end

  def delete_files(files_to_delete)
    # TODO
    files_to_delete.each do |file| 
      log("--  Deleting file #{file} on s3")
      delete_file(file)
    end
  end

  def delete_file(filename)
    obj = @bucket.object(filename).delete
  end

  def generate_md5_local_file(filename)
    path_to_file = "#{MAGIC_DIR_PATH}/#{filename}"
    file = File.open(path_to_file)
    sha256 = Digest::SHA256.file file
    sha256.hexdigest
  end
end # end class

box = Tomboxs3.new(REGION, BUCKET_NAME)
box.monitor
