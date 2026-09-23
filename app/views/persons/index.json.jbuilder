json.persons @persons do |person|
  json.extract! person, :id, :name, :status, :prototype_face_id
  json.face_count person.face_count
  json.representative_url person.representative_url
  json.aliases person.aliases do |alias_record|
    json.extract! alias_record, :id, :alias
  end
end

json.suggestions @suggestions do |suggestion|
  json.extract! suggestion, :id, :run_id, :confidence, :status, :person_id
  json.face_count suggestion.face_count
  json.representative_url suggestion.representative_url
  json.faces suggestion.face_assignments do |assignment|
    json.face_id assignment.face_id
    json.distance assignment.distance
    json.crop_url assignment.face&.crop_path ? "/persons/faces/#{assignment.face_id}/crop" : nil
  end
end

json.enrichment @enrichment
