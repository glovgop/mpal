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
      state :proposition_proposee do
        validates :date_de_visite, :assiette_subventionnable_amount, presence: { message: :blank_feminine }
        validates :travaux_ht_amount, :travaux_ttc_amount, presence: true
        validate  :validate_theme_count
      end
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

      after_transition to: :en_cours do |projet, _transition|
        ProjetMailer.notification_engagement_operateur(projet).deliver_later!
        EvenementEnregistreurJob.perform_later(label: 'choix_intervenant', projet: projet, producteur: projet.operateur)
      end
      event :etablissement_de_dossier do
        transition to: :en_cours
      end

      after_transition to: :proposition_proposee do |projet, _transition|
        ProjetMailer.notification_validation_dossier(projet).deliver_later!
        EvenementEnregistreurJob.perform_later(label: 'validation_proposition', projet: projet, producteur: projet.operateur)
      end
      event :proposer do
        transition to: :proposition_proposee
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
      state :operateurs_suggested do
        validate :suggested_operateurs_validation

        def suggested_operateurs_validation
          return if invitations.where(suggested: true).present?
          errors[:base] << I18n.t('recommander_operateurs.errors.blank')
        end
      end
      state :operateur_contacted
      state :operateur_commited do
        validate :operateur_validation

        def operateur_validation
          return if operateur
          errors[:base] << "Vous devez choisir un opérateur"
        end
      end

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

      # TODO: pass by a specific controller action and redirect to trigger this
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

      before_transition to: :operateurs_suggested do |projet, transition|
        operateur_ids = transition.args[0]
        if projet.operateur.present?
          raise "Cannot suggest an operator: the projet is already committed with an operator (#{projet.operateur.raison_sociale})"
        end

        projet.invitations.where(suggested: true).each do |invitation|
          invitation.update(suggested: false)
          invitation.destroy! unless invitation.contacted
        end

        operateur_ids.each do |operateur_id|
          projet.invitations.find_or_create_by(intervenant_id: operateur_id).update(suggested: true)
        end
      end
      after_transition to: :operateurs_suggested do |projet, _transition|
        ProjetMailer.recommandation_operateurs(projet).deliver_later!
      end
      event :suggest_operateurs do
        transition to: :operateurs_suggested
      end

      before_transition to: :operateur_contacted do |projet, transition|
        operateur_to_contact = transition.args[0]
        previous_operateur = projet.contacted_operateur
        next if previous_operateur == operateur_to_contact

        if projet.operateur.present?
          raise "Cannot invite an operator: the projet is already committed with an operator (#{projet.operateur.raison_sociale})"
        end

        invitation = Invitation.where(projet: projet, intervenant: operateur_to_contact).first_or_create!
        invitation.update(contacted: true)
        Projet.notify_intervenant_of(invitation)

        if previous_operateur
          previous_invitation = projet.invitations.where(intervenant: previous_operateur).first
          ProjetMailer.resiliation_operateur(previous_invitation).deliver_later!
          if previous_invitation.suggested
            previous_invitation.update(contacted: false)
          else
            previous_invitation.destroy!
          end
        end
      end
      event :contact_operateur do
        transition to: :operateur_contacted
      end

      before_transition to: :operateur_committed do |projet, transition|
        committed_operateur = transition.args[0]
        raise "Commiting with an operateur expects a projet in `prospect` state, but got a `#{statut}` state instead" unless projet.prosect?
        raise "To commit with an operateur there should be no pre-existing operateur" unless projet.operateur.blank?
        raise "Cannot commit with an operateur: the operateur is empty" unless committed_operateur.present?

        projet.update(operateur: committed_operateur)
      end
      after_transition to: :operateur_committed do |projet, _transition|
        projet.etablissement_de_dossier
      end
      event :commit_with_operateur do
        transition to: :operateur_committed
      end
    end
  end
end
