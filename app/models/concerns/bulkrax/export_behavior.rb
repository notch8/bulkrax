# frozen_string_literal: true
module Bulkrax
  module ExportBehavior
    extend ActiveSupport::Concern

    delegate :export_type, :exporter_export_path, to: :importerexporter

    def build_for_exporter
      build_export_metadata
      write_files if export_type == 'full'
    end

    def build_export_metadata
      raise StandardError, 'not implemented'
    end

    def work
      @work ||= ActiveFedora::Base.find(self.identifier)
    end

    def write_files
      return if work.is_a?(Collection)
      work.file_sets.each do |fs|
        path = File.join(exporter_export_path, 'files')
        FileUtils.mkdir_p(path)
        file = filename(fs)
        next if file.blank?
        File.open(File.join(path, file), 'wb') do |f|
          f.write(URI.parse(fs.original_file.uri).open)
          f.close
        end
      end
    end

    # Append the file_set id to ensure a unique filename
    def filename(file_set)
      return if file_set.original_file.blank?
      fn = file_set.original_file.file_name.first
      ext = Mime::Type.lookup(file_set.original_file.mime_type).to_sym
      if fn.include?(file_set.id)
        return fn if fn.end_with?(ext.to_s)
        return "#{fn}.#{ext}"
      else
        return "#{file_set.id}_#{fn}" if fn.end_with?(ext.to_s)
        return "#{file_set.id}_#{fn}.#{ext}"
      end
    end
  end
end
