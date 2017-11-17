module ProjetStateMachine
  extend ActiveSupport::Concern

  STATUSES = [
    :prospect,
    :en_cours,
    :proposition_enregistree,
    :proposition_proposee,
    :transmis_pour_instruction,
    :en_cours_d_instruction
  ]

  included do
    enum statut: {
      prospect: 0,
      en_cours: 1,
      proposition_enregistree: 2,
      proposition_proposee: 3,
      transmis_pour_instruction: 5,
      en_cours_d_instruction: 6
    }

    StateMachines::Machine.ignore_method_conflicts = true
    state_machine :statut, initial: :prospect do
      state :prospect do
        validate :imposition_year

        def imposition_year
          return if avis_impositions.map(&:is_valid_for_current_year?).all?
          errors[:base] << I18n.t("projets.composition_logement.avis_imposition.messages.annee_invalide", year: 2.years.ago.year)
        end
      end

      state :en_cours
      state :proposition_enregistree
      state :proposition_proposee
      state :transmis_pour_instruction
      state :en_cours_d_instruction

      before_transition to: :prospect do |projet, transition|
        ProjetInitializer.new.initialize_projet(projet.numero_fiscal, projet.reference_avis, projet)
      end
      after_transition to: :prospect do |projet, transition|
        EvenementEnregistreurJob.perform_later(label: 'creation_projet', projet: projet)
      end
      event :initialiser do
        transition :prospect => :prospect
      end
    end
  end
end
