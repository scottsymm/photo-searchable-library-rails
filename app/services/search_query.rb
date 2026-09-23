class SearchQuery
  FIELDS = %w[who place before after tag].freeze

  def self.parse(raw)
    result = { text: "" }
    free = []
    raw.to_s.strip.split(/\s+/).reject(&:blank?).each do |token|
      if (match = token.match(/^(who|place|before|after|tag):(.+)$/i))
        result[match[1].downcase.to_sym] = match[2]
      else
        free << token
      end
    end
    result[:text] = free.join(" ")
    result
  end
end
