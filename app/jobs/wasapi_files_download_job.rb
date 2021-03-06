# frozen_string_literal: true

# Methods for Downloading Wasapi Files.
class WasapiFilesDownloadJob < ApplicationJob
  queue_as :download
  require 'open-uri'

  after_perform do |job|
    UserMailer.notify_collection_downloaded(job.arguments.first.id,
                                            job.arguments.second.id).deliver_now
    logger.info 'Email sent to: ' + job.arguments.first.email.to_s
  end

  def perform(user_id, collection_id)
    wasapi_username = user_id.wasapi_username
    wasapi_password = user_id.wasapi_password
    download_files = WasapiFile.where('user_id = ? AND collection_id = ?',
                                      user_id, collection_id)
    Parallel.each(download_files, in_threads: 5) do |wasapi_file|
      download_path = ENV['DOWNLOAD_PATH'] +
                      '/' + wasapi_file.account.to_s +
                      '/' + wasapi_file.collection_id.to_s + '/' + 'warcs/'
      download_path_filename = download_path + wasapi_file.filename
      FileUtils.mkdir_p download_path
      if File.exist?(download_path_filename)
        check_file = Digest::MD5.file(download_path_filename).hexdigest
        if check_file == wasapi_file.checksum_md5
          logger.info 'File exists: ' + download_path_filename
        end
        if check_file != wasapi_file.checksum_md5
          logger.info 'Checksum mismatch:' + download_path_filename
          FileUtils.rm(download_path_filename)
          logger.info 'Downloading: ' + wasapi_file.location_archive_it
          download = open(wasapi_file.location_archive_it,
                          http_basic_authentication: [wasapi_username,
                                                      wasapi_password])
          IO.copy_stream(download, download_path_filename)
          logger.info 'Downloaded: ' + wasapi_file.location_archive_it
        end
      end
      if !File.exist?(download_path_filename)
        logger.info 'Downloading: ' + wasapi_file.location_archive_it
        download = open(wasapi_file.location_archive_it,
                        http_basic_authentication: [wasapi_username,
                                                    wasapi_password])
        IO.copy_stream(download, download_path_filename)
        logger.info 'Downloaded: ' + wasapi_file.location_archive_it
      end
    end
    CollectionsSparkJob.set(queue: :spark)
                       .perform_later(user_id.id, collection_id.id)
  end
end
