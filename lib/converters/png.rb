module Converters::PNG
  def self.from_pdf(pdf_path, dest_path, opts={})
    OBF::PNG.from_pdf(pdf_path, dest_path, opts)
  end
  
  def self.from_obf(obf, dest_path)
    OBF::PNG.from_obf(obf, dest_path)
  end
  
  def self.from_coughdrop(board, dest_path)
    json = Converters::CoughDrop.to_external(board)
    OBF::PNG.from_external(json, dest_path)
  end
end