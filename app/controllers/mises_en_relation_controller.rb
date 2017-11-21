class MisesEnRelationController < ApplicationController
  layout "inscription"

  before_action :assert_projet_courant
  before_action do
    set_current_registration_step Projet::STEP_MISE_EN_RELATION
  end

  def show
    if rod_response.scheduled_operation? && (@projet_courant.preeligibilite(@projet_courant.annee_fiscale_reference) != :plafond_depasse)
      @operateur = rod_response.operateurs.first
      @action_label = action_label
      render :scheduled_operation
      return
    end
    @demande = @projet_courant.demande
    if pris.blank?
      Rails.logger.error "Il n’y a pas de PRIS disponible pour le département #{@projet_courant.departement} (projet_id: #{@projet_courant.id})"
      return redirect_to projet_demandeur_departement_non_eligible_path(@projet_courant)
    end
    @pris = pris
    @page_heading = I18n.t("demarrage_projet.mise_en_relation.assignement_pris_titre")
    @action_label = action_label
  end

  def update
    @projet_courant.update_attribute(
      :disponibilite,
      params[:projet][:disponibilite]
    ) if params[:projet].present?

    eligible = @projet_courant.preeligibilite(@projet_courant.annee_fiscale_reference) != :plafond_depasse

    # TODO: find a way to manage flash messages by projet state
    if (@projet_courant.intervenants.include?(pris) || rod_response.scheduled_operation?) && eligible
      operateur = rod_response.operateurs.first
      flash[:success] = t("invitations.messages.succes", intervenant: operateur.raison_sociale)
    else
      flash[:success] = t("invitations.messages.succes", intervenant: pris.raison_sociale)
    end
    @projet_courant.validate_mise_en_relation(rod_response)
    redirect_to projet_path(@projet_courant)
  rescue => e
    Rails.logger.error e.message
    raise e
    redirect_to(
      projet_mise_en_relation_path(@projet_courant),
      alert: t("demarrage_projet.mise_en_relation.error")
    )
  end

  private

  def rod_response
    @rod_response ||= if ENV['ROD_ENABLED'] == 'true'
                        Rod.new(RodClient).query_for(@projet_courant)
                      else
                        FakeRodResponse.new(ENV['ROD_ENABLED'])
                      end
  end

  def pris
    !@projet_courant.eligible? ? rod_response.pris_eie : rod_response.pris
  end

  def action_label
    if needs_mise_en_relation?
      t("demarrage_projet.action")
    else
      t("projets.edition.action")
    end
  end

  def needs_mise_en_relation?
    @projet_courant.contacted_operateur.blank? && @projet_courant.invited_pris.blank?
  end
end
