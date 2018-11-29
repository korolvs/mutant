# frozen_string_literal: true

Mutant::Meta::Example.add :lambda do
  source '->() {}'

  singleton_mutations
end
