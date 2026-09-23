class PersonAlias < ApplicationRecord
  belongs_to :person
  before_validation { self[:alias] = self[:alias].to_s.strip }
  validates :alias, presence: true, uniqueness: { scope: :person_id }
end
