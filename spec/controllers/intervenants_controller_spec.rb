require "rails_helper"
require "support/api_particulier_helper"
require "support/api_ban_helper"
require "support/mpal_helper"

describe IntervenantsController do
  describe "#index" do
    let(:projet_without_user) { create :projet, :prospect }
    let(:projet_with_user)    { create :projet, :en_cours, :with_assigned_operateur }
    let(:agent_operateur)     { projet_with_user.agent_operateur }
    let(:demandeur)           { projet_with_user.demandeur_user }

    context "quand je suis un agent" do
      it "je peux voir mes contacts si je suis agent du projet" do
        authenticate_as_agent agent_operateur
        get :index, params: { dossier_id: projet_with_user.id }
        expect(response).to render_template(:index)
      end
    end

    context "quand je suis un demandeur" do
      it "je peux voir mes contacts si j'ai un projet et au moins un agent associé" do
        authenticate_as_user demandeur
        get :index, params: { projet_id: projet_with_user.id }
        expect(response).to render_template(:index)
      end

      it "je ne peux pas voir les contacts sinon" do
        authenticate_as_project projet_without_user.id
        get :index, params: { projet_id: projet_without_user.id }
        expect(response).not_to render_template(:index)
      end
    end
  end
end
