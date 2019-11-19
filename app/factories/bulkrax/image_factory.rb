if defined?(Image)
  module Bulkrax
    class ImageFactory < ObjectFactory
      include WithAssociatedCollection

      self.klass = Image
      # A way to identify objects that are not Hydra minted identifiers
      self.system_identifier_field = Bulkrax.system_identifier_field

      # TODO: add resource type?
      # def create_attributes
      #   #super.merge(resource_type: 'Image')
      # end
    end
  end
end
