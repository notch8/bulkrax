module Bulkrax
  module ImportBehavior
    extend ActiveSupport::Concern

    def build_for_importer
      begin
        build_metadata
        raise CollectionsCreatedError unless collections_created?
        @item = factory.run
      rescue StandardError => e
        status_info(e)
      else
        status_info
      end
      return @item
    end

    def find_or_create_collection_ids
      self.collection_ids
    end

    # override this to ensure any collections have been created before building the work
    def collections_created?
      true
    end

    def build_metadata
      raise 'Not Implemented'
    end

    def rights_statement
      parser.parser_fields['rights_statement']
    end

    # try and deal with a couple possible states for this input field
    def override_rights_statement
      %w[true 1].include?(parser.parser_fields['override_rights_statement'].to_s)
    end

    def add_rights_statement
      self.parsed_metadata['rights_statement'] = [parser.parser_fields['rights_statement']] if override_rights_statement || self.parsed_metadata['rights_statement'].blank?
    end

    def add_visibility
      self.parsed_metadata['visibility'] = 'open' if self.parsed_metadata['visibility'].blank?
    end

    def add_collections
      if find_or_create_collection_ids.present?
        self.parsed_metadata['collections'] = []
        self.parsed_metadata['collections'] += find_or_create_collection_ids.map { |c| { id: c } }
      end
    end

    def factory
      @factory ||= Bulkrax::ObjectFactory.new(self.parsed_metadata, identifier, replace_files, user, factory_class)
    end

    def factory_class

      if self.parsed_metadata&.[]('model').present?
        fc = self.parsed_metadata&.[]('model').is_a?(Array) ? self.parsed_metadata&.[]('model').first : self.parsed_metadata&.[]('model')
      elsif self.mapping&.[]('work_type').present?
        fc = self.parsed_metadata&.[]('work_type').is_a?(Array) ? self.parsed_metadata&.[]('work_type').first : self.parsed_metadata&.[]('work_type')
      else
        fc = Bulkrax.default_work_type
      end 
      fc.constantize
    rescue NameError => e
      raise NameError.new(e.message)
    rescue
      Bulkrax.default_work_type.constantize
    end
  end
end