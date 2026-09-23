json.persons @persons do |person|
  json.extract! person, :id, :name, :status
  json.face_count person.face_count
  json.representative_url person.representative_url
  json.aliases person.aliases do |alias_record|
    json.extract! alias_record, :id, :alias
  end
end
