# frozen_string_literal: true

module Bulkrax
  class ApplicationParser
    attr_accessor :importerexporter
    delegate :only_updates, :limit, :current_exporter_run, :current_importer_run, :errors,
             :seen, :increment_counters, :parser_fields, :user,
             :exporter_export_path, :exporter_export_zip_path, :importer_unzip_path, :validate_only,
             :status, :status_info, :status_at,
             to: :importerexporter

    def self.parser_fields
      {}
    end

    def self.export_supported?
      false
    end

    def self.import_supported?
      true
    end

    def initialize(importerexporter)
      @importerexporter = importerexporter
    end

    # @api
    def entry_class
      raise 'must be defined'
    end

    # @api
    def collection_entry_class
      raise 'must be defined'
    end

    # @api
    def records(_opts = {})
      raise 'must be defined'
    end

    def perform_method
      if self.validate_only
        'perform_now'
      else
        'perform_later'
      end
    end

    def import_file_path
      @import_file_path ||= self.parser_fields['import_file_path']
    end

    def create_collections
      raise 'must be defined' if importer?
    end

    def create_works
      raise 'must be defined' if importer?
    end

    # Optional, define if using browse everything for file upload
    def retrieve_cloud_files(files); end

    def write_import_file(file)
      path = File.join(path_for_import, file.original_filename)
      FileUtils.mv(
        file.path,
        path
      )
      path
    end

    def path_for_import
      path = File.join(Bulkrax.import_path, importerexporter.id.to_s)
      FileUtils.mkdir_p(path) unless File.exist?(path)
      path
    end

    # Optional, only used by certain parsers
    # Other parsers should override with a custom or empty method
    # Will be skipped unless the record is a Hash
    def create_parent_child_relationships
      parents.each do |key, value|
        parent = entry_class.where(
          identifier: key,
          importerexporter_id: importerexporter.id,
          importerexporter_type: 'Bulkrax::Importer'
        ).first

        # not finding the entries here indicates that the given identifiers are incorrect
        # in that case we should log that
        children = value.map do |child|
          entry_class.where(
            identifier: child,
            importerexporter_id: importerexporter.id,
            importerexporter_type: 'Bulkrax::Importer'
          ).first
        end.compact.uniq

        if parent.present? && (children.length != value.length)
          # Increment the failures for the number we couldn't find
          # Because all of our entries have been created by now, if we can't find them, the data is wrong
          Rails.logger.error("Expected #{value.length} children for parent entry #{parent.id}, found #{children.length}")
          break if children.empty?
          Rails.logger.warn("Adding #{children.length} children to parent entry #{parent.id} (expected #{value.length})")
        end
        parent_id = parent.id
        child_entry_ids = children.map(&:id)
        ChildRelationshipsJob.perform_later(parent_id, child_entry_ids, current_importer_run.id)
      end
      status_info
    rescue StandardError => e
      status_info(e)
    end

    def parents
      @parents ||= setup_parents
    end

    def setup_parents
      pts = []
      records.each do |record|
        r = if record.respond_to?(:to_h)
              record.to_h
            else
              record
            end
        next unless r.is_a?(Hash)
        children = if r[:children].is_a?(String)
                     r[:children].split(/\s*[:;|]\s*/)
                   else
                     r[:children]
                   end
        next if children.blank?
        pts << {
          r[:source_identifier] => children
        }
      end
      pts.blank? ? pts : pts.inject(:merge)
    end

    def setup_export_file
      raise 'must be defined' if exporter?
    end

    def write_files
      raise 'must be defined' if exporter?
    end

    def importer?
      importerexporter.is_a?(Bulkrax::Importer)
    end

    def exporter?
      importerexporter.is_a?(Bulkrax::Exporter)
    end

    # Override to add specific validations
    def valid_import?
      true
    end

    def find_or_create_entry(entryclass, identifier, type, raw_metadata = nil)
      entry = entryclass.where(
        importerexporter_id: importerexporter.id,
        importerexporter_type: type,
        identifier: identifier
      ).first_or_create!
      entry.raw_metadata = raw_metadata
      entry.save!
      entry
    end

    # @todo - review this method
    def record(identifier, _opts = {})
      return @record if @record

      @record = entry_class.new(self, identifier)
      @record.build
      return @record
    end

    def total
      0
    end

    def write
      write_files
      zip
    end

    def unzip(file_to_unzip)
      WillowSword::ZipPackage.new(file_to_unzip, importer_unzip_path).unzip_file
    end

    def zip
      WillowSword::ZipPackage.new(exporter_export_path, exporter_export_zip_path).create_zip
    end
  end
end
