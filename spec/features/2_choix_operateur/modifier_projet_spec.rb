require 'rails_helper'
require 'support/mpal_features_helper'
require 'support/api_ban_helper'

feature "Modifier le projet :" do

  shared_examples :can_edit_demandeur do |resource_name|
    let(:resource_name) { resource_name }
    def resource_path(projet)
      send("#{resource_name}_path", projet)
    end
    def resource_demandeur_path(projet)
      send("#{resource_name}_demandeur_path", projet)
    end

    scenario "je peux modifier les informations personnelles du demandeur" do
      visit resource_path(projet)
      within 'article.occupants' do
        click_link I18n.t('projets.visualisation.lien_edition')
      end

      expect(page).to have_current_path resource_demandeur_path(projet)
      expect(find('#demandeur_principal_civilite_mr')).to be_checked
      expect(page).to have_field('Adresse postale', with: '65 rue de Rome, 75008 Paris')

      fill_in :projet_adresse_postale,   with: Fakeweb::ApiBan::ADDRESS_PORT
      fill_in :projet_adresse_a_renover, with: Fakeweb::ApiBan::ADDRESS_MARE
      fill_in :projet_tel, with: '01 10 20 30 40'

      click_button I18n.t('projets.edition.action')

      expect(page).to have_content('01 10 20 30 40')
      expect(page).to have_current_path resource_path(projet)
      expect(page).to have_content Fakeweb::ApiBan::ADDRESS_PORT
      expect(page).to have_content Fakeweb::ApiBan::ADDRESS_MARE
    end
  end

  shared_examples :can_edit_demande do
    scenario "je peux modifier les informations de l'habitation et de la demande" do
      within 'article.projet' do
        click_link I18n.t('projets.visualisation.lien_edition')
      end
      fill_in :demande_annee_construction, with: '1950'
      click_button I18n.t('projets.edition.action')
      expect(page).to have_content(1950)
      # TODO: tester la modification des travaux demandés
    end
  end

  context "en tant que demandeur" do
    let(:projet) { create(:projet, :prospect, :with_invited_operateur) }
    before { signin(projet.numero_fiscal, projet.reference_avis) }

    it_behaves_like :can_edit_demandeur, "projet"
    it_behaves_like :can_edit_demande
  end

  context "en tant qu'opérateur" do
    let(:projet) { create(:projet, :prospect, :with_committed_operateur) }
    let(:agent_operateur) { create :agent, intervenant: projet.operateur }

    before { login_as agent_operateur, scope: :agent }

    it_behaves_like :can_edit_demandeur, "dossier"
  end
end
