class AddWorkflowStatusToBulkraxExporter < ActiveRecord::Migration[5.1]
  def change
    add_column :bulkrax_exporters, :workflow_status, :string unless column_exists?(:bulkrax_exporters, :workflow_status)
  end
end
