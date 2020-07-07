require 'aws-sdk-s3'
require "json"
require 'fileutils'

BUCKET_NAME = ENV["TOMBOXS3_BUCKET_NAME"] || "tomboxs3"
REGION  = ENV["TOMBOXS3_REGION"] || "ca-central-1" # canada
MANIFEST_FILE_NAME = ENV["MANIFEST_FILE_NAME"] || "s3_manifest.json"
MAGIC_DIR_PATH = ENV["TOMBOXS3_MAGIC_DIR_PATH"] || "/Users/tompedron/Downloads/tomboxs3_magic_dir"
MANIFEST_FILE_PATH = "#{MAGIC_DIR_PATH}/#{MANIFEST_FILE_NAME}".freeze

class Tomboxs3

  def execute()
    # # init_manifest_file unless manifest.present?
    # pp BUCKET_NAME
    # pp REGION
    # pp MAGIC_DIR_PATH
    # pp MANIFEST_FILE_NAME
    # pp MANIFEST_FILE_PATH

    connect_to_bucket(REGION, BUCKET_NAME)
  end

  def connect_to_bucket(region, bucket_name)
    # pp "CONNECT TO BUCKET"
    # # load credentials from disk
    # creds = YAML.load(File.read('creds.yml'))

    # Aws::S3::Client.new(
    #   access_key_id: creds['access_key_id'],
    #   secret_access_key: creds['secret_access_key']
    # )

    @s3 = Aws::S3::Resource.new(
      # access_key_id: creds['access_key_id'],
      # secret_access_key: creds['secret_access_key'],
      region: region
    )

    @bucket = @s3.bucket(bucket_name) #if @s3.present? # 'my-bucket'
  end

  # def print_files_in_s3_bucket()# Show only the first 50 items
  #   pp "PRINT FILES IN S3 BUCKET"
  #   index = 1
  #   @bucket.objects.each do |item|
  #     s3obj = item.get
  #     puts "#{index}:  #{item.key}"
  #     puts "        metadata:   #{s3obj.metadata}"
  #     # puts "        md5:   #{item.etag}"
  #     # puts "        URL:   #{item.presigned_url(:get)}"
  #     # puts "        Bucket:   #{item.bucket}"
  #     #validate_against_local(item)

  #     index+=1
  #   end
  # end

  def find_file_in_s3_bucket(filename)
    #remote_file = @bucket.objects[filename]

    remote_file = nil
    @bucket.objects.each do |curr_file|
      pp filename
      pp curr_file.key
      if filename == curr_file.key
        s3obj = curr_file.get
        puts "REMOTE FILE:  #{curr_file.key}"
        puts "        metadata:   #{s3obj.metadata}"
        return [curr_file, s3obj]
      end
    end
    [nil, nil]
  end

  def validate_against_local(item)
    #manifest.
  end

  # def download_item_from_remote(key)
  #   item = @bucket.object(key)
  #   ite.get(response_target: "#{MAGIC_DIR_PATH}/#{key}")
  # end

  def manifest_item(key)
   a = manifest_items.find {|item| item['name'] == key}
   pp "AAAA"
   pp a
   pp "BBBB"

   a
  end

  def manifest_items
    manifest["data"]
  end

  def manifest
    begin
      @manifest ||= JSON.load(File.open(MANIFEST_FILE_PATH))
    rescue => exception
      return nil
    end
  end

  def init_manifest_file
    FileUtils.cp("s3_manifest_template.json", MANIFEST_PATH)
    manifest
  end

  def generate_manifest_from_dir_contents
    existing_files = []
    new_files = []
    files_in_dir = []
    files_to_update = []
    
    pp "GENERATE MANIFEST FROM MAGIC DIR"
    index = 1
    Dir.foreach(MAGIC_DIR_PATH) do |filename|
      next if filename == '.' or filename == '..' or filename == MANIFEST_FILE_NAME
      puts "#{index}.  #{filename}"
      # puts "        md5:   #{generate_md5_local_file(filename)}"

      file_array = find_file_in_s3_bucket(filename)
      file = file_array[0]
      s3obj = file_array[1]

      !file.nil? ? existing_files << filename : new_files << filename
      files_in_dir << filename

      if !s3obj.nil?
        local_md5 = manifest_item(filename)["md5"]
        remote_md5 = s3obj.metadata["md5"]

        pp "Local md5  = #{local_md5}"
        pp "Remote md5 = #{remote_md5}"
        file_updated = local_md5  != remote_md5

        files_to_update << filename if file_updated
      end

      index+=1
    end

    pp "FILES IN DIR"
    pp files_in_dir
    pp "EXISTING FILES"
    pp existing_files
    pp "NEW FILES"
    pp new_files
    pp "FILES TO UPDATE"
    pp files_to_update

    add_files_to_manifest(files_in_dir) #existing_files + new_fles)
    upload_new_files(new_files) if new_files.any?
    update_files(files_to_update) if files_to_update.any?
  end

  def add_files_to_manifest(files)
    json_array = []
    files.each do |curr_file|
      json_array << {
        name: curr_file,
        md5: generate_md5_local_file(curr_file)
      }
    end

    pp "MANIFEST DATA"
    manifest_data = {
      data: json_array
    }
    pp manifest_data

    File.write(MANIFEST_FILE_PATH, JSON.pretty_generate(manifest_data)) #manifest_data.to_json)
  end


  def upload_new_files(new_files)
    pp "UPLOAD NEW"
    new_files.each do |file|
      upload_file(file)
    end
  end

  def update_files(files_to_update)
    pp "UPDATE EXISTING"
    files_to_update.each do |file|
      upload_file(file)
    end
  end

  def upload_file(filename)
    
    pp filename
    # Create the object to upload
    obj = @bucket.object(filename)

    # Metadata to add
    metadata = {
      "md5": generate_md5_local_file(filename),
    }

    # Upload it  
    pp "UPLOAD"    
    obj.upload_file("#{MAGIC_DIR_PATH}/#{filename}", metadata: metadata)
  end

  def generate_md5_local_file(filename)
    path_to_file = "#{MAGIC_DIR_PATH}/#{filename}"
    file = File.open(path_to_file)
    sha256 = Digest::SHA256.file file
    sha256.hexdigest
  end

end # end class


box = Tomboxs3.new

box.execute
# box.print_files_in_s3_bucket
box.generate_manifest_from_dir_contents
