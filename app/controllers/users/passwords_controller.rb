class Users::PasswordsController < Devise::PasswordsController
  include ApplicationConcern

  # GET /resource/password/new
  def new
    @page_heading = "Mot de passe perdu ?"
    super
  end

  # POST /resource/password
  def create
    super
  end

  # GET /resource/password/edit?reset_password_token=abcdef
  def edit
    @page_heading = "Changement de mot de passe"
    super
  end

  # PUT /resource/password
  def update
    super
  end

protected
  def after_resetting_password_path_for(resource)
    projet_as_demandeur = resource.projet_as_demandeur
    projet_as_demandeur ? projet_path(projet_as_demandeur) : root_path
  end

  # The path used after sending reset password instructions
  def after_sending_reset_password_instructions_path_for(resource_name)
    root_path
  end
end

