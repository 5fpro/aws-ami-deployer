class BaseModel
  def initialize(attrs = {})
    (attrs || {}).each { |attr, value| public_send("#{attr}=", value) }
  end
end
