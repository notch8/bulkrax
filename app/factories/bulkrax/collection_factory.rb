module Bulkrax
  class CollectionFactory < ObjectFactory
    self.klass = Collection
    self.system_identifier_field = Bulkrax.system_identifier_field

    def find_or_create
      collection = find
      return collection if collection
      run(&:save!)
    end

    def update
      raise "Collection doesn't exist" unless object
      object.attributes = update_attributes
      run_callbacks(:save) do
        object.save!
      end
      log_updated(object)
    end
  end
end
