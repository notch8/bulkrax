module Bulkrax
  class BagitParser < ApplicationParser
    def self.export_supported?
      false # @todo will be supported
    end

    def entry_class
      self.parser_fields['metadata_format'].constantize
    end

    def collection_entry_class
      self.parser_fields['metadata_format'].gsub('Entry', 'CollectionEntry').constantize
    rescue
      Entry
    end

    def import_fields
      raise 'No metadata files were found' if metadata_paths.blank?
      @import_fields ||= metadata_paths.map do |path|
        entry_class.fields_from_data(entry_class.read_data(path))
      end.flatten.compact.uniq
    end

    # Assume a single metadata record per path
    # Create an Array of all metadata records, one per file
    def records(_opts = {})
      raise 'No metadata files were found' if metadata_paths.blank?
      @records ||= metadata_paths.map do |path|
        data = entry_class.read_data(path)
        entry_class.data_for_entry(data, path)
      end
    end

    # Find or create collections referenced by works
    # If the import data also contains records for these works, they will be updated
    # during create works
    def create_collections
      collections.each do |collection_record|
        # split by ; |
        collection_record.split(/\s*[;|]\s*/).each do |collection|
          metadata = {
            title: [collection],
            Bulkrax.system_identifier_field => [collection],
            visibility: 'open',
            collection_type_gid: Hyrax::CollectionType.find_or_create_default_collection_type.gid
          }
          new_entry = find_or_create_entry(collection_entry_class, collection, 'Bulkrax::Importer', metadata)
          ImportWorkCollectionJob.perform_now(new_entry.id, current_importer_run.id)
        end
      end
    end

    def create_works
      records.each_with_index do |record, index|
        next if record[:source_identifier].blank?
        break if !limit.nil? && index >= limit

        seen[record[:source_identifier]] = true
        new_entry = find_or_create_entry(entry_class, record[:source_identifier], 'Bulkrax::Importer', record)
        ImportWorkJob.perform_later(new_entry.id, current_importer_run.id)
        increment_counters(index)
      end
    rescue StandardError => e
      errors.add(:base, e.class.to_s.to_sym, message: e.message)
    end

    def collections
      records.map { |record| record[:collection] }.flatten.compact.uniq
    end

    def collections_total
      collections.size
    end

    def total
      metadata_paths.count
    end

    def import_file_path
      @import_file_path ||= real_import_file_path
    end

    def required_elements?(keys)
      return if keys.blank?
      !required_elements.map { |el| keys.map(&:to_s).include?(el) }.include?(false)
    end

    def required_elements
      %w[title source_identifier]
    end

    # @todo - remove/refactor after factory refactory
    def files_path
      Rails.root.to_s
    end

    # private

      def real_import_file_path
        if file? && zip?
          unzip(self.parser_fields['import_file_path'])
          return File.join(importer_unzip_path, self.parser_fields['import_file_path'].split('/').last.gsub('.zip', ''))
        else
          self.parser_fields['import_file_path']
        end
      end

      # Gather the paths to all bags; skip any stray files
      def bag_paths
        if bag?(import_file_path)
          [import_file_path]
        elsif bags?(import_file_path)
          Dir.glob("#{import_file_path}/*").reject { |d| File.file?(d) }
        else
          raise 'No valid bags found'
        end
      end

      def metadata_file_name
        raise 'The metadata file name must be specified' if self.parser_fields['metadata_file_name'].blank?
        self.parser_fields['metadata_file_name']
      end

      # Gather the paths to all metadata files matching the metadata_file_name
      def metadata_paths
        @metadata_paths ||= bag_paths.map do |b|
          Dir.glob("#{b}/**/*").select { |f| File.file?(f) && f.ends_with?(metadata_file_name) }
        end.flatten.compact
      end

      # Is this a file?
      def file?
        File.file?(self.parser_fields['import_file_path'])
      end

      # Is this a zip file?
      def zip?
        MIME::Types.type_for(self.parser_fields['import_file_path']).include?('application/zip')
      end

      # Is the directory is a bag?
      def bag?(path)
        File.exist?(File.join(path, 'bagit.txt')) && BagIt::Bag.new(path).valid?
      end

      # Are the immediate sub-directories of this directory bags?
      # All or nothing
      def bags?(path)
        result = true
        Dir.glob("#{path}/*").reject { |d| File.file?(d) }.each do |dir|
          result = false unless bag?(dir)
        end
        result
      end
  end
end
