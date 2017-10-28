defmodule ApathyDrive.DamageType do
  use ApathyDrive.Web, :model

  schema "damage_types" do
    field :name, :string

    has_many :abilities_damage_types, ApathyDrive.AbilityDamageType
    has_many :abilities, through: [:abilities_damage_types, :ability]
  end

end
