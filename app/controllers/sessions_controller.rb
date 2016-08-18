class SessionsController < ApplicationController
  skip_before_action :authentifie
  def new
  end

  def create
    # reset_session
    contribuable = ApiParticulier.new.retrouve_contribuable(params[:numero_fiscal], params[:reference_avis])
    if contribuable
      session[:numero_fiscal] = params[:numero_fiscal]
      projet = ProjetEntrepot.par_numero_fiscal(params[:numero_fiscal])
      if projet
        redirect_to projet
      else
        create_projet_and_redirect
      end
    else
      redirect_to new_session_path, alert: t('sessions.invalid_credentials')
    end
  end

  def create_projet_and_redirect
    constructeur = ProjetConstructeur.new(ApiParticulier.new, ApiBan.new)
    projet = constructeur.initialise_projet(params[:numero_fiscal], params[:reference_avis])
    if projet.save
      EvenementEnregistreurJob.perform_later(label: 'creation_projet', projet: projet)
      notice = t('projets.messages.creation.corps')
      flash[:notice_titre] = t('projets.messages.creation.titre', usager: projet.usager)
      redirect_to projet_path(projet), notice: notice
    else
      redirect_to new_session_path, alert: t('sessions.erreurs.creation_projet')
    end
  end
end
