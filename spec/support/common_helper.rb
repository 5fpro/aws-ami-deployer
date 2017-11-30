module CommonHelper
  def fixtures_path(file_path)
    File.join(App.root, 'spec', 'fixtures', file_path)
  end
end
