class ChangeEntryLastError < ActiveRecord::Migration[5.1]

  def change
    # Use raw query to change text to JSON as last_error field is now serialized
    results = ActiveRecord::Base.connection.execute("SELECT id, last_error from bulkrax_entries WHERE last_error IS NOT null AND last_error LIKE '%\n\n%'")
    results.each do | error |
      old_errors = error['last_error'].split("\n\n")
      new_error = {
        'error_class' => 'unknown', 
        'error_message' => old_errors.first,
        'error_trace' => old_errors.last
      }
      ActiveRecord::Base.connection.execute("UPDATE bulkrax_entries SET last_error = '#{new_error.to_json}' WHERE id = '#{error['id']}'")
    end
  end

end
