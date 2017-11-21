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
        transition to: :prospect
      end
    end

    state_machine :prospect_state, initial: :initial do
      state :initial
      state :demandeur do
        validate :demandeur_validation

        def demandeur_validation
          return if occupants.where(demandeur: true).present?
          errors[:base] << I18n.t('demarrage_projet.demandeur.erreurs.missing_demandeur')
        end
      end
      state :avis_imposition
      state :occupants
      state :demande
      state :eligibilite
      state :mise_en_relation

      before_transition :initial => :demandeur do |projet, transition|
        projet_params = transition.args[0]&.to_hash
        demandeur_params = transition.args[1]&.to_hash
        projet_params.assert_valid_keys(
          'adresse_postale',
          'adresse_a_renover',
          'tel',
          'email',
          'demandeur',
          'demandeur_attributes',
          'personne_attributes'
        )
        if projet_params.fetch('personne_attributes', {empty: nil}).values.all?(&:blank?)
          projet_params.delete('personne_attributes')
        end

        # TODO: creates orphelin nodes
        projet.adresse_postale = ProjetInitializer.new.precise_adresse(
          projet_params.delete('adresse_postale'),
          previous_value: projet.adresse_postale,
          required: true
        )

        # TODO: creates orphelin nodes
        projet.adresse_a_renover = ProjetInitializer.new.precise_adresse(
          projet_params.delete('adresse_a_renover'),
          previous_value: projet.adresse_a_renover,
          required: false
        )

        # TODO: establish that as nested attributes
        if (demandeur = projet_params.delete('demandeur')).present?
          new_demandeur = projet.change_demandeur(demandeur)
          new_demandeur.update(demandeur_params)
        end

        projet.assign_attributes(projet_params)
      end
      event :enregistrer_demandeur do
        transition to: :demandeur
      end

      # TODO: pass by a specific action to trigger this
      event :validate_avis_imposition do
        transition to: :avis_imposition
      end
      event :validate_occupants do
        transition to: :occupants
      end
      event :validate_demande do
        transition to: :demande
      end
      event :validate_eligibilite do
        transition to: :eligibilite
      end
      before_transition to: :mise_en_relation do |projet, transition|
        eligible = projet.preeligibilite(projet.annee_fiscale_reference) != :plafond_depasse
        rod_response = transition.args[0]
        pris = !projet.eligible? ? rod_response.pris_eie : rod_response.pris

        if (projet.intervenants.include?(pris) || rod_response.scheduled_operation?) && eligible
          operateur = rod_response.operateurs.first
          projet.contact_operateur!(operateur.reload)
          projet.commit_with_operateur!(operateur.reload)
        else
          invitation = projet.invite_pris!(pris)
          Projet.notify_intervenant_of(invitation) if projet.eligible?
        end
        projet.invite_instructeur! rod_response.instructeur
      end
      event :validate_mise_en_relation do
        transition to: :mise_en_relation
      end
    end
  end
end
