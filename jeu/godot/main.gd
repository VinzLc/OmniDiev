extends Node2D
##
## La salle se lit, elle ne s'écrit plus.
##
## Rien ici ne connaît Wellan, le Château ni le Roi. La scène ouvre deux
## fichiers — le monde produit depuis le Codex, et la salle écrite à la main —
## et bâtit ce qu'ils décrivent. Ajouter un personnage tient en trois nombres et
## l'identifiant de sa fiche ; son nom, son rôle et ses liens en viennent tout
## seuls.
##
## C'est ce qui rend l'échelle tenable : 365 personnages et 57 lieux attendent
## dans monde.json, et aucun ne demandera qu'on retouche ce fichier.

const TUILE := 16
const SPRITE := 32
const TAILLADE := 64
const FEU_COTE := 24          ## côté d'une image de braise
const ECLAT_COTE := 32        ## côté d'une image de gerbe
const PORTRAIT := 84          ## côté du visage dans la boîte de dialogue          ## côté d'une image d'arc, plus large que le sprite
## Un pas un peu plus vif. À cinquante-huit, traverser une salle de vingt-six
## tuiles demandait sept secondes, et l'on sentait la longueur avant de sentir
## le lieu.
const VITESSE := 80.0

## La course, sur P.
##
## Gratuite, et sans jauge. Les jeux dont celui-ci s'inspire donnent des
## chaussures de course qu'on ne retire jamais : facturer le sprint ferait
## surveiller une barre au lieu de regarder la salle. Le pas normal reste, il
## sert à s'approcher de quelqu'un sans le dépasser.
##
## Soixante-quinze pour cent plus vif : la galerie des Sept se traverse en trois
## secondes et demie au lieu de six.
const VITESSE_COURSE := 140.0
const CADENCE := 7.0

## Rangée de la planche pour chaque direction regardée.
const RANGEE := { "sud": 0, "nord": 1, "ouest": 2, "est": 3 }

const DONNEES := "res://donnees/"
const Partie := preload("res://partie.gd")
## Le banc d'essai ne se charge que si on l'appelle : le jeu livré ne le voit
## jamais s'exécuter, et il ne pèse rien dans le fichier qu'il vérifie.
const Banc := preload("res://banc.gd")
const Interface := preload("res://interface.gd")
const Sons := preload("res://sons.gd")
const Donnees := preload("res://donnees.gd")
const Tactile := preload("res://tactile.gd")

## Le combat, en clair. Ces nombres sont à nous ; ce qui vient du texte, c'est
## que la carapace des hommes-insectes boit la magie.
## Vingt-quatre points au lieu de huit : à huit, deux coups de lance suffisaient
## et l'on rejouait la vague avant d'avoir compris ce qui l'avait tuée.
## Les statistiques, à l'ancienne.
##
## Chacune commande exactement un nombre du jeu, et la base reproduit à l'unité
## près l'équilibre d'avant : vingt-quatre points de vie, quatre-vingts pixels
## par seconde, un dégât d'épée, sept de sort, aucune réduction. Ajouter des
## statistiques ne doit pas rééquilibrer le jeu en douce — sinon on ne saurait
## plus si un chapitre est devenu difficile parce qu'il l'est ou parce qu'un
## chiffre a bougé sans qu'on regarde.
##
## L'agilité n'existe pas : c'est la vitesse de déplacement qui prend sa place,
## et elle se voit tout de suite, sans table de probabilités.
const BASE := { "force": 5, "vitesse": 8, "vitalite": 6, "sagesse": 7, "defense": 0 }

## Ce que chaque statistique commande, et comment elle s'y convertit.
const VIE_PAR_VITALITE := 4
const PIXELS_PAR_VITESSE := 10.0
const FORCE_PAR_DEGAT := 5
const DEFENSE_PAR_POINT := 6

const VIE_WELLAN := 24

## La vie revient, mais bien plus lentement que l'énergie : assez pour qu'une
## escarmouche gagnée se paie moins cher, pas assez pour tout réparer en
## restant immobile.
const REGAIN_VIE := 0.55       ## points par seconde
const ENERGIE_MAX := 100.0
const COUT_DU_SORT := 25.0
const REGAIN := 14.0          ## énergie par seconde
const REPOS_EPEE := 0.38      ## secondes entre deux coups
## Jusqu'où porte le fer, et la demi-largeur du balayage.
##
## La zone couvrait autrefois de sept pixels derrière Wellan à trente-sept
## devant, pendant que l'arc dessiné n'en atteignait que dix-neuf. On frappait
## donc ce qu'on ne voyait pas atteindre, et le coup paraissait court — un
## joueur juge la portée sur ce qu'il voit, non sur ce qui touche.
##
## Les deux valeurs sont relevées sur l'arc lui-même — de quinze à trente-sept
## pixels devant Wellan, et plus rien derrière. Ce qu'on voit est ce qui touche.
const PORTEE_EPEE := 37.0
const LARGEUR_COUP := 11.0
const DEGATS_EPEE := 1
## Le feu de Theandras porte deux fois plus loin dans la chair qu'une lame, et
## va vite : c'est un sort qui coûte le quart de l'énergie, il doit valoir son
## prix. Il ne prend toujours pas sur les carapaces.
const DEGATS_SORT := 7
const VITESSE_SORT := 245.0
const PORTEE_SORT := 260.0

## Les statistiques courantes, base plus équipement.
##
## Recalculées à l'équipement, non lues à chaque image : `Partie.equipe()` ouvre
## le fichier de sauvegarde, et le faire soixante fois par seconde reviendrait à
## lire un disque pour savoir à quelle vitesse marcher.
var _stats := {}

var _monde: Dictionary
var _salle: Dictionary
var _salle_id := ""
var _scene: Dictionary

## Ce que la salle courante a bâti, et qu'elle remporte en partant.
##
## Tout reste enfant direct de la scène : un conteneur intermédiaire aurait
## rangé le décor plus proprement, mais le tri par profondeur trie une fratrie,
## et le mobilier serait passé d'un bloc devant ou derrière Wellan.
var _du_decor: Array[Node] = []

## Qui se trouve où, salle par salle.
##
## Le fichier de salle donne l'effectif de départ ; les étapes le corrigent.
## Sans ce registre, revenir dans la salle du trône la rebâtirait telle qu'elle
## est écrite — Armène de retour alors qu'elle est repartie, la Reine absente
## alors qu'elle vient d'entrer. C'est la dégradation silencieuse habituelle :
## rien n'échoue, le chapitre ment.
var _effectif := {}

## Les portes de la salle courante, sous une clé « passage:x:y ».
var _passages := {}
var _chapitre := ""
var _libre := false          ## scène imposée en ligne de commande : on ne note rien

## Où en est le chapitre, et à qui l'on a déjà parlé dans l'étape en cours.
var _etape := 0
var _parles := {}
var _habitants := {}

var _energie := ENERGIE_MAX
## La vie se regagne par fractions de point : on garde la part décimale ici,
## sinon un regain plus lent qu'un point par seconde n'arriverait jamais.
var _vie_dodue := float(VIE_WELLAN)
var _prochain_coup := 0.0
var _ennemis: Array = []
var _traits: Array = []       ## les sorts en vol
var _vaincu := false

var _wellan: Combattant
var _camera: Camera2D
var _vue: Sprite2D
var _direction := "sud"
var _phase := 0.0

var _a_portee := {}            ## tous ceux dont on est assez près
var _proche := ""              ## celui qu'on aborderait, le plus proche d'entre eux
var _interlocuteur := ""       ## à qui l'on parle en ce moment
## Une page sait de quel genre elle est.
##
## Une parole et une description ne se lisent pas de la même façon : l'une sort
## d'une bouche, l'autre est ce que le joueur constate. Les confondre dans un
## même cadre effaçait la différence, et les maladresses des personnages — qui
## font le sel de ces échanges — se perdaient dans la narration.
var _pages: Array = []
var _page := 0
var _ouverte := false

## L'interface. Le jeu lui dit ce qu'il veut montrer ; où et comment cela
## s'affiche ne le regarde pas.
var _ui: CanvasLayer

## Les bruitages. Même partage : le jeu dit ce qu'il veut faire entendre.
var _sons: Node

var _marcheurs: Array = []   ## ceux qui entrent ou sortent, en chemin
var _bulles := {}            ## les bulles de parole, par identifiant de fiche
var _objets := {}            ## ce qu'on peut examiner, par clé
var _offres := {}            ## par fiche : la pièce qu'un habitant tend à Wellan
var _cloture_dite := false
## Ce qu'on a entendu, étape par étape, pour tout le chapitre. `_parles` ne vaut
## que pour l'étape en cours ; ceci survit et sert à rattraper.
var _entendus := {}
var _cle_courante := ""
var _flottement := 0.0
var _choix_pause := 0
var _en_pause := false
var _au_codex := false
## Le coffre qu'on vient de lire, et dont le contenu s'ouvrira après.
var _butin_en_attente := ""
var _au_butin := ""
var _choix_butin := 0
var _contenu_butin := []
var _a_la_carte := false
var _choix_carte := 0
var _escales := []
## Le chapitre en cours a-t-il été ouvert ? Il ne s'ouvre qu'une fois, quand on
## met le pied dans sa salle — et l'on peut en ressortir et y revenir.
var _chapitre_ouvert := false
var _aux_chapitres := false
var _choix_chapitre := 0
var _liste_chapitres := []
var _au_sac := false
var _choix_sac := 0
var _categorie_sac := 0
var _contenu_sac := []
var _aux_commandes := false
var _commandes_depuis_pause := false
var _choix_codex := 0
var _fiches_codex := []
var _recit_capture := false   ## une seule image de description suffit au contrôle
var _invite_capture := false
var _bulles_capture := false
var _butin_capture := false
var _wellan_capture := false
var _mare: Sprite2D = null
var _banc                     ## le harnais de vérification, quand il est demandé    ## la mare de sang, gardée entre deux morts


func _ready() -> void:
	# Vue de dessus : ce qui est plus bas à l'écran est plus près, donc devant.
	y_sort_enabled = true

	_monde = _lire(DONNEES + "monde.json")
	_chapitre = _scene_demandee()
	_noter(_chapitre)
	_scene = _lire(DONNEES + "scenes/%s.json" % _chapitre)
	# Le monde est ouvert : on reprend là où l'on était, non là où le chapitre
	# se joue. La salle du chapitre n'est plus qu'une destination parmi d'autres,
	# et c'est au joueur d'y aller.
	_salle_id = str(Partie.retenu("salle", ""))
	if _salle_id == "" or not FileAccess.file_exists(DONNEES + "salles/%s.json" % _salle_id):
		_salle_id = str(_scene.get("salle", ""))
	# Un chapitre imposé — en ligne de commande ou rejoué depuis le menu — dépose
	# là où il commence. « Joue ce chapitre » veut dire « pose-moi à son départ » ;
	# reprendre la position gardée obligerait à traverser la carte avant de
	# pouvoir l'éprouver.
	if _libre:
		_salle_id = str(_scene.get("salle", ""))
	_salle = _lire(DONNEES + "salles/%s.json" % _salle_id)
	if _monde.is_empty() or _salle.is_empty() or _scene.is_empty():
		push_error("Données absentes. Lancer : npm run jeu:donnees")
		return

	_declarer_les_touches()
	# Un premier calcul avant Wellan : c'est lui qui donne sa vie maximale.
	_recalculer_les_stats()
	_batir_wellan()
	_ui = Interface.new()
	add_child(_ui)
	# Les commandes du pouce, qui se retirent d'elles-mêmes hors tactile.
	add_child(Tactile.new())
	# Le second vient après l'interface, non avant : il pousse les jauges, et
	# les pousser vers une interface qui n'existe pas encore levait une erreur à
	# chaque lancement. Elle était sans effet — la passe de physique remettait
	# les jauges d'aplomb à l'image suivante — et personne ne la voyait, parce
	# qu'on ne lit pas la sortie d'erreur d'un jeu qui s'ouvre correctement.
	_recalculer_les_stats()
	_sons = Sons.new(_monde.get("sons", []), _monde.get("musiques", []))
	add_child(_sons)

	# La souris survole et clique dans la fenêtre de butin. Le clavier fait la
	# même chose ; l'interface se contente de signaler, le jeu décide.
	_ui.butin_survole.connect(func(rang: int) -> void:
		if _au_butin == "" or rang < 0 or rang >= _contenu_butin.size() or rang == _choix_butin:
			return
		_choix_butin = rang
		_sons.jouer("menu-deplace")
		_rafraichir_le_butin())
	_ui.butin_pris.connect(_prendre_du_butin)
	# La salle vient après l'interface : elle lui parle en se bâtissant — les
	# bulles de parole demandent à savoir si le chapitre est achevé.
	_batir_la_salle()
	_tomber_la_nuit()

	# Wellan s'inscrit au Codex sans qu'on lui adresse la parole : on ne se
	# rencontre pas soi-même. Le recueil n'est donc jamais tout à fait vide, et
	# la première fiche qu'on y lit est celle qu'on incarne.
	Partie.rencontrer("wellan")

	# Et ce qu'il porte déjà. Pris puis équipé une seule fois : si le joueur
	# repose son épée plus tard, `prendre` rend faux au lancement suivant et
	# l'on ne la lui remet pas de force.
	for d in _monde.get("depart", []):
		var porte := str((d as Dictionary)["id"])
		if Partie.prendre(porte):
			Partie.equiper(str((d as Dictionary)["emplacement"]), porte)
	_recalculer_les_stats()

	_ouvrir_le_chapitre_si_on_y_est()

	# Les commandes, une fois par partie. Les remontrer à chaque chapitre — la
	# scène se recharge d'un chapitre à l'autre — serait une porte à pousser
	# toutes les dix minutes. Le menu les garde disponibles pour toujours.
	if not bool(Partie.retenu("commandes_vues", false)):
		Partie.retenir("commandes_vues", true)
		_ouvrir_les_commandes(false)

	# Le drapeau peut arriver des deux côtés de `++` selon la façon dont on
	# lance : on regarde les deux listes plutôt que d'imposer un ordre.
	if OS.get_cmdline_args().has("--capture") or OS.get_cmdline_user_args().has("--capture"):
		_banc = Banc.new(self)
		_banc._capturer()
	elif OS.get_cmdline_user_args().has("--effets"):
		_banc = Banc.new(self)
		_banc._capturer_les_effets()
	elif OS.get_cmdline_user_args().has("--verifier"):
		# Le contrôle d'un seul chapitre, sans capture ni fenêtre.
		_banc = Banc.new(self)
		_banc._verifier()


## Les touches d'action.
##
## Déclarées ici plutôt que dans project.godot : la sérialisation des
## événements d'entrée dans ce fichier est illisible et se corrompt à la
## moindre retouche à la main. Trois lignes de code valent mieux.
func _declarer_les_touches() -> void:
	# `physical_keycode` désigne la position de la touche : W/A/S/D y tombent
	# sur Z/Q/S/D en AZERTY. Une seule déclaration sert les deux dispositions.
	for paire in [["ui_up", KEY_W], ["ui_left", KEY_A], ["ui_down", KEY_S], ["ui_right", KEY_D]]:
		var deja := false
		for e in InputMap.action_get_events(paire[0]):
			if e is InputEventKey and e.physical_keycode == paire[1]:
				deja = true
		if not deja:
			var k := InputEventKey.new()
			k.physical_keycode = paire[1]
			InputMap.action_add_event(paire[0], k)

	for nom in [["frapper", KEY_J], ["lancer", KEY_K], ["pause", KEY_ESCAPE],
			["suivant", KEY_ENTER], ["courir", KEY_P]]:
		if InputMap.has_action(nom[0]):
			continue
		InputMap.add_action(nom[0])
		var touche := InputEventKey.new()
		touche.physical_keycode = nom[1]
		InputMap.action_add_event(nom[0], touche)


## Quel chapitre jouer ?
##
## Celui qu'on impose en ligne de commande — `++ --scene i-01` — et sinon celui
## où l'on en était. La partie se poursuit d'elle-même : c'est ce qui fait d'une
## suite de scènes une histoire.
##
## Les arguments passent après `++`, non avant : tout ce qui précède appartient
## au moteur, et un mot sans tiret y est pris pour un chemin de scène à charger.
func _scene_demandee() -> String:
	var arguments := OS.get_cmdline_user_args()

	# Un chapitre rejoué depuis le menu se joue comme une scène imposée à la
	# main : rien ne se note. On le consomme au passage — la fois d'après,
	# Entrée ramène le joueur là où il en était vraiment.
	#
	# Avant le drapeau de ligne de commande, et non après : une demande faite
	# en cours de partie l'emporte sur ce qui a lancé le processus. Au démarrage
	# la valeur est toujours vide, donc l'ordre ne change rien au lancement — il
	# rend seulement la branche atteignable quand on éprouve avec `--scene`.
	if Partie.rejoue != "":
		var demande := Partie.rejoue
		Partie.rejoue = ""
		_libre = true
		return demande

	var i := arguments.find("--scene")
	if i >= 0 and i + 1 < arguments.size():
		_libre = true
		return arguments[i + 1]

	var suite := Partie.campagne()
	var repris: String = str(Partie.courante().get("chapitre", ""))
	if repris != "" and suite.has(repris):
		return str(repris)
	return str(suite[0]) if not suite.is_empty() else "i-01"


## Note où l'on en est. Une scène imposée à la main ne compte pas.
func _noter(chapitre: String) -> void:
	if _libre:
		return
	Partie.noter(chapitre)


## Le chapitre suivant dans l'ordre de lecture, vide s'il n'y en a plus.
func _chapitre_suivant() -> String:
	return Partie.suivant(_chapitre)


func _lire(chemin: String) -> Dictionary:
	return Donnees.lire(chemin)


## Relit l'équipement et en tire tous les nombres du combat.
func _stats_depuis(porte: Dictionary) -> Dictionary:
	var calcul := BASE.duplicate()
	var catalogue: Dictionary = _monde.get("prises", {})
	for emplacement in porte:
		var fiche: Dictionary = catalogue.get(str(porte[emplacement]), {})
		for cle in fiche.get("bonus", {}):
			calcul[cle] = int(calcul.get(cle, 0)) + int(fiche["bonus"][cle])
	return calcul


func _recalculer_les_stats() -> void:
	_stats = _stats_depuis(Partie.equipe())

	if _wellan == null:
		return
	var avant := _wellan.vie_max
	_wellan.vie_max = _vie_max()
	# Ce qu'on gagne en vitalité se gagne aussi en vie présente : sinon relever
	# le plafond laisse la jauge à moitié pleine et ressemble à une blessure.
	if _wellan.vie_max > avant:
		_wellan.vie += _wellan.vie_max - avant
	_wellan.vie = mini(_wellan.vie, _wellan.vie_max)
	_vie_dodue = float(_wellan.vie)
	_wellan.reduction = _reduction()
	_jauger(_wellan.vie, _wellan.vie_max)


func _vie_max() -> int:
	return int(_stats.get("vitalite", BASE["vitalite"])) * VIE_PAR_VITALITE


func _vitesse() -> float:
	return maxf(1.0, float(_stats.get("vitesse", BASE["vitesse"]))) * PIXELS_PAR_VITESSE


func _degats_epee() -> int:
	return 1 + int(_stats.get("force", BASE["force"]) - BASE["force"]) / FORCE_PAR_DEGAT


func _degats_sort() -> int:
	return int(_stats.get("sagesse", BASE["sagesse"]))


func _reduction() -> int:
	return int(_stats.get("defense", 0)) / DEFENSE_PAR_POINT


func _taille() -> Vector2i:
	var t: Array = _salle.get("taille", [26, 15])
	return Vector2i(int(t[0]), int(t[1]))


## Le sol, en tuiles de Wang.
##
## Chaque tuile se choisit par ses quatre coins : on demande à chaque sommet de
## la grille s'il est tapis ou dalle, et les quatre réponses forment le numéro de
## la colonne. C'est ce qui permet au tapis d'avoir n'importe quelle forme sans
## qu'on dessine un seul cas particulier.
func _batir_le_sol() -> void:
	var lieu: Dictionary = _monde["lieux"].get(_salle.get("lieu", ""), {})
	var tuiles = lieu.get("tuiles")
	if tuiles == null:
		push_error("Le lieu « %s » n'a pas de tuiles." % _salle.get("lieu", ""))
		return

	var atlas := TileSetAtlasSource.new()
	atlas.texture = load("res://assets/" + str(tuiles))
	atlas.texture_region_size = Vector2i(TUILE, TUILE)
	for i in 16:
		atlas.create_tile(Vector2i(i, 0))

	var jeu := TileSet.new()
	jeu.tile_size = Vector2i(TUILE, TUILE)
	jeu.add_source(atlas, 0)

	var carte := TileMapLayer.new()
	carte.tile_set = jeu
	# Le sol occupe son propre plan, sous tout le reste. Cela libère un plan
	# intermédiaire pour ce qui se pose au sol sans être un personnage — une
	# mare de sang, demain une empreinte ou une ombre.
	carte.z_index = -2
	_poser_dans_la_salle(carte)

	var taille := _taille()
	for y in taille.y:
		for x in taille.x:
			var signature := 0
			for coin in [Vector2i(x, y), Vector2i(x + 1, y), Vector2i(x, y + 1), Vector2i(x + 1, y + 1)]:
				signature = (signature << 1) | _terrain_en(coin)
			carte.set_cell(Vector2i(x, y), 0, Vector2i(signature, 0))


## Lequel des deux terrains occupe ce sommet de la grille ?
##
## Le terrain 0 est le plus sombre du jeu de tuiles, le 1 l'autre. La salle
## nomme son fond et découpe des zones dedans. La convention est explicite
## depuis Zénor : deviner laquelle des deux teintes est laquelle marchait tant
## qu'un tapis vert s'opposait à du dallage gris, et plus du tout dès qu'on a
## peint de l'herbe contre de la pierre claire.
func _terrain_en(sommet: Vector2i) -> int:
	for zone in _salle.get("zones", []):
		if sommet.x >= int(zone["x"]) and sommet.x <= int(zone["x"]) + int(zone["l"]) \
			and sommet.y >= int(zone["y"]) and sommet.y <= int(zone["y"]) + int(zone["h"]):
			return int(zone.get("terrain", 1))
	return int(_salle.get("fond", 1))


## Les murs.
##
## Faute de tuiles murales, la salle est bordée d'une bande sombre et de
## collisions. Le jour où les tuiles arriveront, seul l'habillage changera.
##
## Le mur reste plein derrière une porte : la porte est un battant, non une
## trouée. La percer laisserait Wellan sortir dans le noir qui borde la salle —
## un décor qui n'est le sol de rien.
func _batir_les_murs() -> void:
	var sol := Rect2(Vector2.ZERO, Vector2(_taille()) * TUILE)
	var mur := 8.0

	var cadre := ColorRect.new()
	cadre.color = Color("#0b0a10")
	cadre.position = sol.position - Vector2(mur * 8, mur * 8)
	cadre.size = sol.size + Vector2(mur * 16, mur * 16)
	cadre.z_index = -10
	_poser_dans_la_salle(cadre)

	var corps := StaticBody2D.new()
	_poser_dans_la_salle(corps)
	for bord in [
		Rect2(sol.position.x, sol.position.y - mur, sol.size.x, mur),
		Rect2(sol.position.x, sol.end.y, sol.size.x, mur),
		Rect2(sol.position.x - mur, sol.position.y - mur, mur, sol.size.y + mur * 2),
		Rect2(sol.end.x, sol.position.y - mur, mur, sol.size.y + mur * 2),
	]:
		var forme := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = bord.size
		forme.shape = rect
		forme.position = bord.position + bord.size / 2.0
		corps.add_child(forme)


## ── Les salles ────────────────────────────────────────────────────────────
##
## Le Château ne tient pas dans une pièce. La salle du trône ouvre sur une
## galerie qui dessert la bibliothèque, la salle d'armes et le dortoir : c'est
## le même chapitre, joué dans quatre décors de plus.
##
## Une seule salle vit à la fois. Ce qui n'est pas sous les yeux n'existe qu'en
## registre — l'effectif — et se rebâtit à l'identique quand on repasse la
## porte.

## Tout ce qui appartient à la salle passe par ici.
##
## Une salle qu'on quitte doit remporter exactement ce qu'elle a posé. Nommer au
## départ les nœuds un par un est la façon sûre d'en oublier un, et un nœud
## oublié se retrouve dans la salle suivante, où il n'a rien à faire — un
## brasero au milieu du dortoir sans que rien ne le signale.
##
## Tout reste enfant direct de la scène. Un conteneur aurait rangé le décor plus
## proprement, mais le tri par profondeur ordonne une fratrie : le mobilier
## serait passé d'un bloc devant ou derrière Wellan.
func _poser_dans_la_salle(n: Node) -> void:
	add_child(n)
	_du_decor.append(n)


## Le chapitre en cours se joue-t-il ici ?
func _chapitre_ici() -> bool:
	return _salle_id == str(_scene.get("salle", ""))


## Le lieu où le chapitre en cours attend le joueur.
func _lieu_du_chapitre() -> String:
	var ou := _lire(DONNEES + "salles/%s.json" % str(_scene.get("salle", "")))
	return str(ou.get("lieu", ""))


func _nom_du_lieu(id: String) -> String:
	return str((_monde.get("lieux", {}) as Dictionary).get(id, {}).get("nom", id))


## Ouvre le chapitre si l'on vient de mettre le pied dans sa salle.
##
## C'est le cœur du monde ouvert : achever un chapitre ne transporte plus
## personne. Le suivant est noté, son objectif dit où il attend, et il ne
## commence que le jour où l'on s'y rend. On peut donc traîner, revenir sur ses
## pas, vider un coffre — le chapitre patiente.
func _ouvrir_le_chapitre_si_on_y_est() -> void:
	if not _chapitre_ici():
		_ui.objectif("Se rendre à %s" % _nom_du_lieu(_lieu_du_chapitre()))
		return
	if _chapitre_ouvert:
		return
	_chapitre_ouvert = true
	_entrer_dans_l_etape()
	_annoncer_le_chapitre()


## Quelle musique pour cette salle ?
##
## Le morceau porte le nom du lieu qu'il accompagne — `chateau-d-emeraude.wav`
## pour le lieu `chateau-d-emeraude`. C'est le fichier qui fait la
## correspondance, non une table à tenir : sans fichier au nom du lieu, le lieu
## est silencieux, et c'est tout ce qu'il y a à savoir.
##
## Une scène peut imposer le sien. Une bataille ne se joue pas sur le thème du
## Château, et le jour où Zénor aura sa musique, elle s'écrira dans la scène et
## non dans les quatre salles de la grève.
func _musique_de_la_salle() -> String:
	var impose := str(_scene.get("musique", ""))
	return impose if impose != "" else str(_salle.get("lieu", ""))


func _batir_la_salle() -> void:
	_batir_les_passages()
	_batir_le_sol()
	_batir_les_murs()
	_peupler()
	_rafraichir_les_bulles()
	_borner_la_camera()
	# Après la salle : c'est elle qui dit le lieu. Le morceau ne repart pas si
	# c'est déjà le bon — franchir une porte du Château ne coupe pas la phrase.
	_sons.musique(_musique_de_la_salle())


func _borner_la_camera() -> void:
	var taille := _taille()
	_camera.limit_left = -8
	_camera.limit_top = -8
	_camera.limit_right = taille.x * TUILE + 8
	_camera.limit_bottom = taille.y * TUILE + 8


func _remporter_la_salle() -> void:
	# L'orientation prise en cours de route retourne au registre. Un personnage
	# abordé se tourne vers Wellan et garde cette orientation ; la lui faire
	# reprendre parce qu'on est sorti une minute serait se détourner de lui.
	for entree in _effectif_de(_salle_id):
		var id := str((entree as Dictionary).get("fiche", ""))
		var sens := _sens_regarde(id)
		if sens != "":
			entree["regarde"] = sens

	for n in _du_decor:
		if is_instance_valid(n):
			# Retiré de l'arbre avant d'être libéré. `queue_free` attend la fin
			# de l'image, et d'ici là les zones de parole de l'ancienne salle
			# répondent encore — à l'endroit précis où Wellan vient d'arriver
			# dans la nouvelle, puisque les deux partagent le repère. On se
			# serait retrouvé à parler à quelqu'un qui n'est plus là, dans une
			# salle où il n'a jamais été.
			remove_child(n)
			n.queue_free()
	_du_decor.clear()

	# Ce qui n'appartient à aucune salle mais traîne dans celle-ci : la mare de
	# sang, les sorts en vol. Les emporter dans la salle voisine se lirait comme
	# un défaut d'affichage.
	if _mare != null and is_instance_valid(_mare):
		_mare.queue_free()
	_mare = null
	for trait_en_vol in _traits:
		if is_instance_valid(trait_en_vol["noeud"]):
			(trait_en_vol["noeud"] as Node).queue_free()
	_traits.clear()

	_habitants.clear()
	_objets.clear()
	_passages.clear()
	_bulles.clear()
	_marcheurs.clear()
	_a_portee.clear()
	_proche = ""
	_ui.invite(false)


## Le sens dans lequel un habitant regarde, relu sur sa planche.
func _sens_regarde(id: String) -> String:
	if not _habitants.has(id):
		return ""
	var corps: Node2D = _habitants[id]
	if not is_instance_valid(corps):
		return ""
	for enfant in corps.get_children():
		if enfant is Sprite2D and enfant.texture is AtlasTexture:
			var rang := int((enfant.texture as AtlasTexture).region.position.y / SPRITE)
			for sens in RANGEE:
				if RANGEE[sens] == rang:
					return str(sens)
	return ""


## Qui se trouve dans une salle, qu'on y soit ou non.
func _effectif_de(id_salle: String) -> Array:
	if not _effectif.has(id_salle):
		var salle := _salle if id_salle == _salle_id else _lire(DONNEES + "salles/%s.json" % id_salle)
		_effectif[id_salle] = (salle.get("personnages", []) as Array).duplicate(true)
	return _effectif[id_salle]


func _inscrire_a_l_effectif(id_salle: String, habitant: Dictionary) -> void:
	var liste: Array = _effectif_de(id_salle)
	for entree in liste:
		if str((entree as Dictionary).get("fiche", "")) == str(habitant.get("fiche", "")):
			return
	liste.append(habitant.duplicate(true))


func _rayer_de_l_effectif(id_salle: String, fiche: String) -> void:
	var liste: Array = _effectif_de(id_salle)
	for i in range(liste.size() - 1, -1, -1):
		if str((liste[i] as Dictionary).get("fiche", "")) == fiche:
			liste.remove_at(i)


## Les portes de la salle.
##
## Une porte est un battant dessiné dans le mur et un seuil au sol : on la voit
## avant de la chercher. Elle s'ouvre à la touche de dialogue — un seul verbe
## pour parler, examiner et sortir — plutôt qu'au contact. Au contact, tout
## déplacement qui pose Wellan sur le seuil changerait de salle, et le banc
## d'essai le pose beaucoup.
func _batir_les_passages() -> void:
	for passage in _salle.get("passages", []):
		var place := Vector2i(int(passage["x"]), int(passage["y"]))
		var vers := str(passage.get("vers", ""))
		var arrivee: Array = passage.get("arrivee", [1, 1])

		# Le nom affiché est celui de la salle où l'on va, lu chez elle. Le
		# recopier dans la porte en ferait un second exemplaire, et deux
		# exemplaires d'un nom divergent sans que personne le voie.
		var ailleurs := _lire(DONNEES + "salles/%s.json" % vers)
		if ailleurs.is_empty():
			push_warning("Porte vers une salle inconnue : %s" % vers)
			continue

		var cle := "passage:%d:%d" % [place.x, place.y]
		_passages[cle] = {
			"case": place,
			"vers": vers,
			"arrivee": Vector2i(int(arrivee[0]), int(arrivee[1])),
			"nom": str(ailleurs.get("nom", vers)),
			# Une porte peut n'ouvrir qu'à partir d'un chapitre. La chambre de
			# Kira n'existe pas avant qu'elle arrive, et une pièce meublée pour
			# quelqu'un qui n'est pas encore là se lit comme une faute de suite.
			"des": str(passage.get("des", "")),
			"verrou": str(passage.get("verrou", "")),
		}
		_dessiner_la_porte(place, _verrouillee(_passages[cle]))

		var socle := Node2D.new()
		socle.position = Vector2(place) * TUILE
		_poser_dans_la_salle(socle)
		_zone_de_parole(socle, cle)


## De quel bord une case est-elle ?
func _cote_de(place: Vector2i) -> String:
	var taille := _taille()
	if place.y <= 0:
		return "nord"
	if place.y >= taille.y - 1:
		return "sud"
	if place.x <= 0:
		return "ouest"
	if place.x >= taille.x - 1:
		return "est"
	return ""


const DEHORS := {
	"nord": Vector2(0, -1), "sud": Vector2(0, 1),
	"ouest": Vector2(-1, 0), "est": Vector2(1, 0),
}


## Un battant, dessiné dans la bande sombre qui borde la salle.
##
## Vers le dehors et non vers le dedans : le dallage occupe le plan -2, une
## porte peinte par-dessous y disparaîtrait tout en se déclarant visible.
## Cette porte s'ouvre-t-elle déjà ?
##
## On compare au chapitre qu'on joue, non au plus loin qu'on soit allé : rejouer
## le chapitre I,1 doit retrouver la porte fermée, sinon le Château montrerait
## un état qui n'existait pas encore.
func _verrouillee(porte: Dictionary) -> bool:
	var des := str(porte.get("des", ""))
	if des == "":
		return false
	return Partie.rang(_chapitre) < Partie.rang(des)


func _dessiner_la_porte(place: Vector2i, fermee := false) -> void:
	var cote := _cote_de(place)
	if cote == "":
		push_warning("Porte hors des bords : %s" % place)
		return
	var horizontal := cote == "nord" or cote == "sud"
	var dehors: Vector2 = DEHORS[cote]
	var sol := Rect2(Vector2.ZERO, Vector2(_taille()) * TUILE)

	# Le milieu de l'embrasure : sur la ligne du mur, à la hauteur de la case.
	var milieu := Vector2(place) * TUILE
	match cote:
		"nord": milieu.y = sol.position.y
		"sud": milieu.y = sol.end.y
		"ouest": milieu.x = sol.position.x
		"est": milieu.x = sol.end.x

	# Le seuil de pierre, au sol, côté salle. C'est lui qui se voit de loin et
	# qui dit de quel côté on entre ; le battant, lui, est rasant.
	var seuil := ColorRect.new()
	seuil.color = Color("#9aa6ac")
	seuil.size = Vector2(TUILE + 4.0, 6.0) if horizontal else Vector2(6.0, TUILE + 4.0)
	seuil.position = milieu - seuil.size / 2.0 - dehors * 12.0
	# Au plan -1, comme tout ce qui s'étale au sol : au-dessus du dallage, qui
	# est à -2, et au-dessous de qui marche dessus.
	seuil.z_index = -1
	_poser_dans_la_salle(seuil)

	# Le battant, pris dans la banque de mobilier comme n'importe quel meuble.
	#
	# Il est dessiné de face quelle que soit la paroi. Un battant vu de trois
	# quarts n'a pas de version « de côté » qu'un quart de tour rendrait juste,
	# et les jeux dont celui-ci s'inspire dessinent toutes leurs portes de face.
	#
	# Il enjambe la ligne du mur au lieu de se poser derrière. La caméra ne
	# dépasse jamais le plancher de plus de huit pixels : un battant posé dans
	# la bande sombre tombait aux trois quarts hors du cadre et se lisait comme
	# un éclat de mur.
	var battant := Sprite2D.new()
	var region := AtlasTexture.new()
	region.atlas = load(DONNEES + "objets.png")
	region.region = Rect2(maxi(_mobilier().find("porte"), 0) * SPRITE, 0, SPRITE, SPRITE)
	battant.texture = region
	battant.position = milieu + dehors * 2.0
	battant.z_index = -1
	# Une porte fermée se voit avant qu'on s'y heurte : elle perd ses couleurs.
	# Rien ne serait plus agaçant que de traverser une salle pour découvrir sur
	# place qu'on ne passe pas.
	if fermee:
		battant.modulate = Color(0.45, 0.45, 0.52)
	_poser_dans_la_salle(battant)


## Passer une porte.
##
## On ne quitte pas une salle où quelque chose est encore debout. Fuir une vague
## viderait le combat de son enjeu — et laisserait des adversaires vivants dans
## une salle qu'on cesse de bâtir.
func _franchir(cle: String) -> void:
	var porte: Dictionary = _passages.get(cle, {})
	if porte.is_empty():
		return
	if _verrouillee(porte):
		_reciter([str(porte.get("verrou", "Cette porte ne s'ouvre pas."))])
		return
	if _vague_debout() > 0:
		_reciter(["La porte est là. Ce qui est debout derrière toi ne l'est pas moins."])
		return
	_changer_de_salle(str(porte["vers"]), porte["arrivee"])


func _changer_de_salle(vers: String, arrivee: Vector2i) -> void:
	var suivante := _lire(DONNEES + "salles/%s.json" % vers)
	if suivante.is_empty():
		push_error("Salle inconnue : %s" % vers)
		return

	_remporter_la_salle()
	_salle_id = vers
	_salle = suivante
	# Une arrivée négative veut dire « à l'entrée de la salle » : c'est ce que
	# demande un voyage par la carte, qui ne sait rien des seuils.
	if arrivee.x < 0:
		var d: Array = _salle.get("depart", [1, 1])
		arrivee = Vector2i(int(d[0]), int(d[1]))
	_wellan.position = Vector2(arrivee) * TUILE
	_batir_la_salle()
	# Sans ce recalage, la caméra traverserait la nouvelle salle en glissant
	# depuis la place qu'elle occupait dans l'ancienne.
	_camera.reset_smoothing()
	_ui.lieu(str(_salle.get("nom", "")))
	# On retient où l'on est : le monde est ouvert, donc l'endroit fait partie
	# de la partie au même titre que le chapitre.
	Partie.retenir("salle", _salle_id)
	_ouvrir_le_chapitre_si_on_y_est()


## La vue d'un personnage : sa planche s'il en a une, la silhouette sinon.
##
## Un personnage sans art n'est pas absent du jeu — il y paraît teinté d'après
## son identifiant, et on lui parle. Attendre que l'art soit prêt pour écrire le
## contenu reviendrait à ne jamais avancer.
func _sprite_de(fiche: Dictionary) -> Sprite2D:
	var vue := Sprite2D.new()
	var region := AtlasTexture.new()
	var planche = fiche.get("planche")
	if planche != null:
		region.atlas = load("res://assets/" + str(planche))
	else:
		region.atlas = load(DONNEES + "silhouette.png")
		vue.modulate = Color(fiche.get("teinte", "#736c82"))
	region.region = Rect2(0, 0, SPRITE, SPRITE)
	vue.texture = region
	# Le sprite est calé sur ses pieds : c'est ce point qui touche le sol.
	vue.offset = Vector2(0, -SPRITE / 2.0 + 2)
	return vue


func _batir_wellan() -> void:
	var depart: Array = _salle.get("depart", [1, 1])
	_wellan = Combattant.new()
	_wellan.vie_max = _vie_max()
	_wellan.camp = "ordre"
	_wellan.position = Vector2(float(depart[0]) * TUILE, float(depart[1]) * TUILE)
	add_child(_wellan)

	_vue = _sprite_de(_monde["personnages"].get("wellan", {}))
	_wellan.add_child(_vue)

	# La collision ne prend que le bas du personnage : dans une vue de dessus,
	# seuls ses pieds occupent le sol.
	var forme := CollisionShape2D.new()
	var boite := RectangleShape2D.new()
	boite.size = Vector2(12, 8)
	forme.shape = boite
	forme.position = Vector2(0, -4)
	_wellan.add_child(forme)

	_camera = Camera2D.new()
	_camera.zoom = Vector2(2, 2)
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	_wellan.add_child(_camera)
	_borner_la_camera()

	# Wellan porte sa propre lueur : sans elle, une nuit assez noire pour être
	# une nuit rend le personnage invisible entre deux braseros.
	if _scene.get("ambiance", {}).get("lumieres", false):
		var lueur := PointLight2D.new()
		lueur.texture = _halo(72)
		lueur.color = Color("#dddde4")
		# Wellan est vêtu de noir : sous une nuit assez sombre pour en être une,
		# il disparaît entre deux braseros si sa propre lueur ne le tient pas.
		lueur.energy = 1.4
		_wellan.add_child(lueur)

	_wellan.blesse.connect(func(reste: int, sur: int) -> void:
		# Recaler le compteur décimal sur la vie réelle : sans cela le regain
		# rendrait le point à peine perdu, et l'on ne pourrait plus mourir.
		_vie_dodue = float(reste)
		_jauger(reste, sur))
	_wellan.peri.connect(_perdre)


## Peuplée d'après le registre, non d'après le fichier.
##
## Le fichier dit qui s'y trouvait au lever du rideau. Le registre dit qui s'y
## trouve maintenant — et c'est ce qu'il faut rebâtir en repassant la porte.
func _peupler() -> void:
	_offres = {}
	for habitant in _effectif_de(_salle_id):
		if not _deja_la(habitant):
			continue
		var h: Dictionary = habitant
		if h.has("donne"):
			_offres[str(h.get("fiche", ""))] = h["donne"]
		_faire_entrer(habitant, false)
	for objet in _salle.get("objets", []):
		_batir_objet(objet)


## Cet habitant est-il déjà arrivé dans l'histoire ?
##
## Même mécanisme que le verrou d'une porte, et pour la même raison : Nogait est
## l'Écuyer de Jasson, or les Écuyers ne sont attribués qu'au chapitre I,15. Le
## trouver dans la galerie au chapitre I,1 se lirait comme une faute de suite.
func _deja_la(habitant: Dictionary) -> bool:
	var des := str(habitant.get("des", ""))
	return des == "" or Partie.rang(_chapitre) >= Partie.rang(des)


## Ce qu'un habitant de la salle dit de lui-même, hors de tout chapitre.
##
## C'est ce qui donne de la vie au monde : quelqu'un qui est là parce qu'il
## habite là, non parce qu'une étape l'exige. Ses répliques vivent dans la
## salle, pas dans la scène, donc il parle dans tous les chapitres qu'on y joue.
func _paroles_de_la_salle(id: String) -> Dictionary:
	for habitant in _effectif_de(_salle_id):
		var h: Dictionary = habitant
		if str(h.get("fiche", "")) != id:
			continue
		var dit: Array = h.get("dit", [])
		if dit.is_empty():
			return {}
		return { "cle": "salle:%s:%s" % [_salle_id, id], "lignes": dit }
	return {}


## Le bord de la salle le plus proche d'une case, une tuile au-delà.
##
## C'est par là qu'on entre et qu'on sort quand la scène ne le dit pas : on
## vient du dehors le plus proche, ce qui est presque toujours ce qu'on veut.
func _seuil(place: Vector2i) -> Vector2i:
	var taille := _taille()
	var vers := {
		Vector2i(place.x, -1): place.y,
		Vector2i(place.x, taille.y): taille.y - 1 - place.y,
		Vector2i(-1, place.y): place.x,
		Vector2i(taille.x, place.y): taille.x - 1 - place.x,
	}
	var meilleur := Vector2i(place.x, -1)
	var court := 1 << 30
	for porte in vers:
		if vers[porte] < court:
			court = vers[porte]
			meilleur = porte
	return meilleur


func _faire_entrer(habitant: Dictionary, en_marchant := true) -> void:
	var id := str(habitant["fiche"])
	var fiche: Dictionary = _monde["personnages"].get(id, {})
	if fiche.is_empty():
		push_warning("Fiche inconnue : %s" % id)
		return
	if _habitants.has(id):
		return

	var place := Vector2i(int(habitant["x"]), int(habitant["y"]))
	var arrivee := Vector2(place) * TUILE

	# Qui arrive pendant la scène entre en marchant, depuis le seuil que la
	# scène désigne ou, à défaut, depuis le bord le plus proche. Un personnage
	# qui apparaît d'un coup au milieu de la salle se lit comme un défaut.
	#
	# Sauf s'il était déjà là. Une étape peut poser quelqu'un sans le faire
	# entrer — `"pose": true` — parce que toutes les scènes ne commencent pas
	# par une arrivée : Élund est dans sa tour quand on y monte, il n'y court
	# pas derrière nous.
	var depart := arrivee
	if en_marchant and not bool(habitant.get("pose", false)):
		var seuil := _seuil(place)
		if habitant.has("depuis"):
			seuil = Vector2i(int(habitant["depuis"][0]), int(habitant["depuis"][1]))
		depart = Vector2(seuil) * TUILE

	var corps := StaticBody2D.new()
	corps.position = depart
	_poser_dans_la_salle(corps)

	var vue := _sprite_de(fiche)
	var region: AtlasTexture = vue.texture
	region.region = Rect2(0, RANGEE.get(habitant.get("regarde", "sud"), 0) * SPRITE, SPRITE, SPRITE)
	corps.add_child(vue)

	var forme := CollisionShape2D.new()
	var boite := RectangleShape2D.new()
	boite.size = Vector2(12, 8)
	forme.shape = boite
	forme.position = Vector2(0, -4)
	corps.add_child(forme)

	_zone_de_parole(corps, id)
	_habitants[id] = corps
	if en_marchant and depart != arrivee:
		_marcheurs.append({ "corps": corps, "vue": vue, "cible": arrivee, "phase": 0.0, "sortir": false })


## Il s'en va comme il est venu : à pied, jusqu'au seuil le plus proche.
func _faire_sortir(id: String, en_marchant := true) -> void:
	if not _habitants.has(id):
		return
	_a_portee.erase(id)
	if _proche == id:
		_proche = ""
		_ui.invite(false)

	var corps: Node2D = _habitants[id]
	_habitants.erase(id)

	if not en_marchant:
		corps.queue_free()
		return

	var vue: Sprite2D = null
	for enfant in corps.get_children():
		if enfant is Sprite2D:
			vue = enfant
			break
	if vue == null:
		corps.queue_free()
		return

	var place := Vector2i(corps.position / float(TUILE))
	_marcheurs.append({
		"corps": corps, "vue": vue,
		"cible": Vector2(_seuil(place)) * TUILE, "phase": 0.0, "sortir": true,
	})


## ── Le chapitre ───────────────────────────────────────────────────────────
##
## Une étape attend qu'on ait parlé à quelqu'un, ou à tout un groupe. Quand
## c'est fait, les entrées et sorties qu'elle décrit s'appliquent et l'objectif
## change. Rien de tout cela n'est écrit ici : la scène est un fichier.

## Les étapes du chapitre, la clôture comprise.
##
## `fin` n'est pas un cas à part : c'est la dernière étape, avec sa condition
## comme les autres. La traiter à part obligeait à deux chemins pour la même
## chose, et le chapitre ne pouvait jamais s'achever puisque rien n'attendait
## plus rien.
func _etapes() -> Array:
	var toutes: Array = _scene.get("etapes", []).duplicate()
	var fin: Dictionary = _scene.get("fin", {})
	if not fin.is_empty():
		toutes.append(fin)
	return toutes


func _etape_courante() -> Dictionary:
	var toutes := _etapes()
	return toutes[_etape] if _etape < toutes.size() else {}


func _entrer_dans_l_etape() -> void:
	if _etape >= _etapes().size():
		_achever_le_chapitre()
		return

	var etape := _etape_courante()
	_parles.clear()

	# Ce qu'une étape fait entrer ou sortir concerne la salle du chapitre, où
	# qu'on se trouve. On l'inscrit d'abord au registre, on ne le joue que si
	# l'on est là pour le voir : la salle doit montrer, quand on y revient, ce
	# qui s'y est passé pendant qu'on n'y était pas.
	var chez := str(_scene.get("salle", ""))
	for sortant in etape.get("disparaissent", []):
		_rayer_de_l_effectif(chez, str(sortant))
		_faire_sortir(str(sortant))
	for entrant in etape.get("apparaissent", []):
		_inscrire_a_l_effectif(chez, entrant)
		if _salle_id == chez:
			_faire_entrer(entrant)

	_ui.objectif(str(etape.get("objectif", "")))
	_rafraichir_les_bulles()
	_lever_la_vague(etape)


## Fait débarquer les adversaires de l'étape.
##
## Ils viennent du haut de la carte, côté mer : à Zénor l'ennemi arrive par
## l'eau, et le joueur qui les voit apparaître au même endroit à chaque fois
## comprend d'où vient la menace sans qu'on le lui dise.
func _lever_la_vague(etape: Dictionary) -> void:
	for e in _ennemis:
		if is_instance_valid(e["noeud"]):
			(e["noeud"] as Node).queue_free()
	_ennemis.clear()

	var especes: Dictionary = _scene.get("especes", {})
	var taille := _taille()
	var rang := 0
	for groupe in etape.get("vague", []):
		var espece: Dictionary = especes.get(str(groupe["espece"]), {})
		for n in int(groupe.get("nombre", 1)):
			rang += 1
			var ou := Vector2(
				float(3 + (rang * 5) % (taille.x - 6)) * TUILE,
				float(1 + (rang % 2)) * TUILE)
			_faire_debarquer(str(groupe["espece"]), espece, ou)


func _faire_debarquer(id: String, espece: Dictionary, ou: Vector2) -> void:
	var qui := Combattant.new()
	qui.vie_max = int(espece.get("vie", 3))
	qui.immunise_magie = bool(espece.get("immunise_magie", false))
	qui.position = ou
	add_child(qui)

	# La fiche d'un adversaire est celle de son peuple. Sans planche, il paraît en
	# silhouette de la teinte que la scène lui donne — comme n'importe quel
	# personnage que l'atelier n'a pas encore dessiné.
	var fiche: Dictionary = _monde.get("peuples", {}).get(id, _monde["personnages"].get(id, {}))
	var vue := _sprite_de(fiche)
	if fiche.get("planche") == null:
		vue.modulate = Color(str(espece.get("teinte", "#8b2020")))
	qui.add_child(vue)

	var forme := CollisionShape2D.new()
	var boite := RectangleShape2D.new()
	boite.size = Vector2(12, 8)
	forme.shape = boite
	forme.position = Vector2(0, -4)
	qui.add_child(forme)

	qui.peri.connect(func() -> void:
		_etincelle(qui.global_position + Vector2(0, -10), Color("#d14545"), 0.3)
		_sons.jouer("ennemi-meurt")
		qui.queue_free())

	_ennemis.append({
		"noeud": qui,
		"nom": str(espece.get("nom", id)),
		"degats": int(espece.get("degats", 1)),
		"vitesse": float(espece.get("vitesse", 34.0)),
		"prochain": 0.0,
	})


func _vague_debout() -> int:
	var reste := 0
	for e in _ennemis:
		if not is_instance_valid(e["noeud"]):
			continue
		var qui: Combattant = e["noeud"]
		if qui.vivant():
			reste += 1
	return reste


## Les adversaires marchent sur Wellan et frappent au contact.
func _mener_les_ennemis(delta: float) -> void:
	var maintenant := Time.get_ticks_msec() / 1000.0
	for e in _ennemis:
		if not is_instance_valid(e["noeud"]):
			continue
		var qui: Combattant = e["noeud"]
		if not qui.vivant():
			continue
		var vers: Vector2 = qui.global_position.direction_to(_wellan.global_position)
		var loin: float = qui.global_position.distance_to(_wellan.global_position)
		qui.velocity = vers * float(e["vitesse"]) if loin > 14.0 else Vector2.ZERO
		qui.move_and_slide()
		if loin < 18.0 and maintenant >= float(e["prochain"]):
			e["prochain"] = maintenant + 0.9
			if _wellan.encaisser(int(e["degats"]), "fer"):
				_sons.jouer("griffe")


## Le chapitre est joué : on propose la suite, on note où l'on en est.
## Annonce le chapitre : son rang dans la campagne, son titre, sa source.
func _annoncer_le_chapitre() -> void:
	# La référence au tome et au chapitre a été retirée : elle parle du livre au
	# joueur, là où tout le reste lui parle du monde.
	var suite := Partie.campagne()
	var rang := Partie.rang(_chapitre)
	var entete := "Chapitre %d sur %d" % [rang, suite.size()] if rang > 0 else "Hors campagne"
	_ui.carton(entete, str(_scene.get("titre", _chapitre)))


func _achever_le_chapitre() -> void:
	# Le mot de la fin d'abord, l'écran de fin ensuite : on referme le chapitre
	# avant d'annoncer qu'il est refermé.
	var mot_final: Array = _scene.get("cloture", [])
	if not _cloture_dite and not mot_final.is_empty():
		_cloture_dite = true
		_ui.objectif("")
		_reciter(mot_final)
		return

	var suivant := _chapitre_suivant()
	_noter(suivant if suivant != "" else _chapitre)
	_ui.objectif("")

	if suivant == "":
		_ui.acheve("%s — achevé.\nC'est tout ce qui est écrit à ce jour." % str(_scene.get("titre", "")))
	else:
		# On n'emmène plus personne. Le chapitre suivant est ouvert, et c'est au
		# joueur d'aller là où il attend — par la carte, quand il aura fini de
		# traîner ici.
		_ui.acheve("%s — achevé.\nEntrée pour ouvrir « %s ». Il faudra vous y rendre."
			% [str(_scene.get("titre", "")), Partie.titre(suivant)])


## Wellan tombe.
##
## Un panneau qui s'affiche pendant que le personnage reste debout ne dit pas
## qu'il est mort, il dit que la partie s'arrête. Le sprite bascule donc au sol
## et une mare s'élargit sous lui — c'est ce qu'on voit qui doit porter la
## nouvelle, non le texte par-dessus.
func _perdre() -> void:
	_vaincu = true
	_sons.jouer("wellan-tombe")
	_ui.defaite(true)
	_ui.fermer_dialogue()
	_ui.invite(false)

	_vue.rotation_degrees = 90.0
	_vue.offset = Vector2(0, -8)

	if _mare == null:
		_mare = Sprite2D.new()
		var region := AtlasTexture.new()
		region.atlas = load(DONNEES + "sang.png")
		region.region = Rect2(0, 0, SPRITE, SPRITE)
		_mare.texture = region
		# Entre le sol et les corps.
		#
		# Le tri par profondeur ne sait mettre une chose que *derrière* une
		# autre, jamais dessous : posée assez haut pour passer derrière Wellan,
		# la mare lui coiffait la tête comme un capuchon rouge. Un plan
		# intermédiaire règle ce que l'ordre en y ne peut pas exprimer.
		_mare.z_index = -1
		add_child(_mare)
	# Sur la ligne de sol, sous le corps couché qui s'étend à droite des pieds.
	# Mesuré : à moins sept, la mare occupait y 101 à 132 quand le corps
	# commençait à 133 — elles ne se touchaient pas.
	_mare.position = _wellan.global_position + Vector2(9, -1)
	_mare.visible = true
	_elargir_la_mare()


## La mare s'élargit en trois temps.
func _elargir_la_mare() -> void:
	var region: AtlasTexture = _mare.texture
	for n in 3:
		if not _vaincu:
			return
		region.region = Rect2(n * SPRITE, 0, SPRITE, SPRITE)
		await get_tree().create_timer(0.16).timeout


## Reprendre l'étape : Wellan retrouve son souffle, la vague est relevée.
func _reprendre() -> void:
	_vaincu = false
	_ui.defaite(false)
	_vue.rotation_degrees = 0.0
	_vue.offset = Vector2(0, -SPRITE / 2.0 + 2)
	if _mare != null:
		_mare.visible = false
	_wellan.vie = _wellan.vie_max
	_vie_dodue = float(_wellan.vie_max)
	_jauger(_wellan.vie, _wellan.vie_max)
	_energie = ENERGIE_MAX
	var depart: Array = _salle.get("depart", [1, 1])
	_wellan.position = Vector2(float(depart[0]) * TUILE, float(depart[1]) * TUILE)
	_lever_la_vague(_etape_courante())


## L'étape est-elle satisfaite par ce qu'on vient d'entendre ?
func _avancer_si_possible() -> void:
	var attend: Dictionary = _etape_courante().get("attend", {})
	if attend.is_empty():
		return

	if attend.has("vague_defaite"):
		if _vague_debout() == 0:
			_etape += 1
			_entrer_dans_l_etape()
		return

	if attend.has("parler") and _parles.has(str(attend["parler"])):
		_etape += 1
		_entrer_dans_l_etape()
		return

	if attend.has("parler_tous"):
		var reste := 0
		for id in attend["parler_tous"]:
			if not _parles.has(str(id)):
				reste += 1
		if reste == 0:
			_etape += 1
			_entrer_dans_l_etape()
		else:
			# Un objectif qui décompte vaut mieux qu'un objectif qui répète :
			# le joueur voit ce qui lui reste sans tenir le compte lui-même.
			_ui.objectif("%s (%d)" % [_etape_courante().get("objectif", ""), reste])


## De quoi savoir qu'on peut parler, et à qui.
##
## On retient tous ceux qui sont à portée, et l'on tranche par la distance à
## chaque image plutôt qu'à l'entrée dans la zone.
##
## Le premier jet nommait simplement le dernier entré. Dans une salle où six
## Chevaliers se tiennent à deux tuiles les uns des autres, leurs cercles se
## recoupent, et Wellan abordait quelqu'un qu'il n'avait pas visé — sans qu'on
## puisse rien y faire, puisque se rapprocher ne changeait rien.
func _zone_de_parole(parent: Node2D, id: String) -> void:
	var zone := Area2D.new()
	parent.add_child(zone)

	var forme := CollisionShape2D.new()
	var cercle := CircleShape2D.new()
	cercle.radius = 22
	forme.shape = cercle
	zone.add_child(forme)

	zone.body_entered.connect(func(corps: Node) -> void:
		if corps == _wellan:
			_a_portee[id] = parent)
	zone.body_exited.connect(func(corps: Node) -> void:
		if corps == _wellan:
			_a_portee.erase(id))


## Toutes les étapes du chapitre, la clôture comprise.
func _toutes_les_etapes() -> Array:
	var liste: Array = (_scene.get("etapes", []) as Array).duplicate()
	if _scene.has("fin"):
		liste.append(_scene["fin"])
	return liste


## Ce qu'un personnage a à dire, et sous quelle clé le retenir.
##
## Pendant le chapitre : l'étape en cours, et elle seule. Une fois le chapitre
## achevé : tout ce qui a été écrit pour lui, en commençant par ce qu'on n'a pas
## encore entendu. C'est ainsi qu'on rattrape une réplique manquée sans rejouer
## le chapitre — et il y en a beaucoup à manquer, puisque plusieurs n'ont jamais
## été exigées par un objectif.
func _repliques_de(id: String) -> Dictionary:
	if not _ui.acheve_visible():
		var ici: Dictionary = _etape_courante().get("dialogues", {})
		if ici.has(id):
			return { "cle": "%d:%s" % [_etape, id], "lignes": ici[id] }
		# L'étape n'a rien pour lui : peut-être habite-t-il simplement ici.
		return _paroles_de_la_salle(id)

	var trouvees := []
	for i in _toutes_les_etapes().size():
		var d: Dictionary = (_toutes_les_etapes()[i] as Dictionary).get("dialogues", {})
		if d.has(id):
			trouvees.append({ "cle": "%d:%s" % [i, id], "lignes": d[id] })
	var chez_lui := _paroles_de_la_salle(id)
	if not chez_lui.is_empty():
		trouvees.append(chez_lui)
	for t in trouvees:
		if not _entendus.has(t["cle"]):
			return t
	return trouvees[-1] if not trouvees.is_empty() else {}


## A-t-on quelque chose à échanger avec lui ?
func _abordable(id: String) -> bool:
	if id.begins_with("objet:"):
		return _objets.has(id)
	if id.begins_with("passage:"):
		return _passages.has(id)
	return not _repliques_de(id).is_empty()


func _choisir_l_interlocuteur() -> void:
	var meilleur := ""
	var plus_court := INF
	for id in _a_portee:
		if not _abordable(str(id)):
			continue
		var qui: Node2D = _a_portee[id]
		if not is_instance_valid(qui):
			continue
		var d := _wellan.global_position.distance_to(qui.global_position)
		if d < plus_court:
			plus_court = d
			meilleur = str(id)
	_proche = meilleur
	if not _ouverte:
		# Une porte dit où elle mène : « Espace » seul obligerait à la franchir
		# pour l'apprendre, et à revenir sur ses pas si ce n'était pas là.
		var mot := "Espace"
		if _proche.begins_with("passage:"):
			var porte: Dictionary = _passages[_proche]
			# Une porte fermée annonce qu'elle l'est plutôt que sa destination :
			# nommer un endroit où l'on ne peut pas aller est une promesse.
			mot = ("Fermée  ›  Espace" if _verrouillee(porte)
				else "%s  ›  Espace" % str(porte.get("nom", "")))
		_ui.invite(_proche != "", mot)


## La nuit, quand la scène la demande.
##
## Le chapitre 26 place le débarquement dans le noir. Le jouer en plein jour
## vide la moitié du texte de son sens : les fosses qu'on ne voit pas, les feux
## qu'on allume, la vague qui arrive sans qu'on la distingue. Une teinte
## d'ambiance assombrit tout, les braseros y percent des halos.
func _tomber_la_nuit() -> void:
	var ambiance: Dictionary = _scene.get("ambiance", {})
	if ambiance.is_empty():
		return
	var voile := CanvasModulate.new()
	voile.color = Color(str(ambiance.get("teinte", "#ffffff")))
	add_child(voile)


## Un halo, dessiné plutôt que chargé.
##
## Une lumière ponctuelle veut une texture ; en fabriquer une évite de traîner
## un fichier d'image dont personne ne saurait dire à quoi il sert.
func _halo(rayon: int) -> ImageTexture:
	var cote := rayon * 2
	var image := Image.create(cote, cote, false, Image.FORMAT_RGBA8)
	var centre := Vector2(rayon, rayon)
	for y in cote:
		for x in cote:
			var d := centre.distance_to(Vector2(x, y)) / float(rayon)
			var force := clampf(1.0 - d, 0.0, 1.0)
			# Au carré : la lumière d'un feu décroît vite, un dégradé linéaire
			# donne un disque plat qui ne ressemble à rien.
			image.set_pixel(x, y, Color(1, 1, 1, force * force))
	return ImageTexture.create_from_image(image)


## Un objet du décor, et ce qu'on en dit quand on s'en approche.
##
## Un décor muet n'est qu'un motif. Une torche qu'on peut regarder de près, un
## trône dont on lit l'histoire, une bannière qu'on reconnaît : c'est ce qui
## fait qu'une salle cesse d'être un couloir entre deux dialogues.
func _batir_objet(objet: Dictionary) -> void:
	var genre := str(objet.get("type", ""))
	var ou := Vector2(float(objet["x"]) * TUILE, float(objet["y"]) * TUILE)
	_dessiner_objet(genre, ou, objet)

	var texte: Array = objet.get("texte", [])
	if texte.is_empty():
		return

	# Une clé propre à l'objet : `_proche` désigne indifféremment une fiche ou
	# une chose, et il faut pouvoir les distinguer.
	var cle := "objet:%d:%d" % [int(objet["x"]), int(objet["y"])]
	# Un meuble peut rendre plusieurs pièces — le coffre des cuirs donne le
	# plastron et le casque. On range toujours une liste, quitte à n'en avoir
	# qu'une : le jour où l'on écrit la seconde, rien ne bouge dans le moteur.
	var dedans = objet.get("contient", [])
	if dedans is Dictionary:
		dedans = [dedans]
	_objets[cle] = {
		"nom": str(objet.get("nom", "")),
		"texte": texte,
		"contient": dedans,
	}

	var socle := Node2D.new()
	socle.position = ou
	_poser_dans_la_salle(socle)
	_zone_de_parole(socle, cle)
	_habitants[cle] = socle


## Les sortes de mobilier, dans l'ordre de la planche `objets.png`.
##
## Lues dans `monde.json`, où la production les a inscrites d'après le contenu du
## dossier. Une liste écrite ici devait s'accorder avec celle du script, et deux
## listes ne s'accordent pas longtemps : celle des planches à copier est restée
## figée sur deux fichiers pendant que dix existaient, et le jeu se lançait sans
## Kira ni la Reine sans que rien ne le signale. Ajouter un meuble ne demande
## donc plus qu'un fichier dans `jeu/art/objets/`.
func _mobilier() -> Array:
	return _monde.get("mobilier", [])

func _dessiner_objet(genre: String, ou: Vector2, objet: Dictionary) -> void:
	# Une silhouette par sorte, tirée d'une planche dessinée par calcul.
	#
	# Le premier jet peignait le même carré coloré pour tout : un trône, une
	# bannière et un coffre s'y ressemblaient, et un décor où tout est le même
	# carré ne se regarde pas deux fois.
	#
	# En Sprite2D et non en ColorRect : un Control ne participe pas au tri par
	# profondeur et se dessine dans l'ordre de l'arbre.
	var vue := Sprite2D.new()
	var n := _mobilier().find(genre)
	if n < 0:
		push_warning("Sorte de mobilier inconnue : %s" % genre)
	var region := AtlasTexture.new()
	region.atlas = load(DONNEES + "objets.png")
	region.region = Rect2(maxi(n, 0) * SPRITE, 0, SPRITE, SPRITE)
	vue.texture = region
	# Calé par le bas, comme un personnage : un trône ou une bannière montent
	# plus haut qu'une tuile, et c'est leur pied qui touche le sol.
	vue.offset = Vector2(0, -SPRITE / 2.0 + 2)
	vue.position = ou
	_poser_dans_la_salle(vue)

	if genre == "brasier" and _scene.get("ambiance", {}).get("lumieres", false):
		var feu := PointLight2D.new()
		feu.texture = _halo(96)
		feu.color = Color("#f0d174")
		feu.energy = 1.5
		feu.position = ou
		_poser_dans_la_salle(feu)


func _jauge(couche: CanvasLayer, haut: int, fond: Color, plein: Color) -> ColorRect:
	var creux := ColorRect.new()
	creux.color = fond.darkened(0.5)
	creux.anchor_left = 1.0
	creux.anchor_right = 1.0
	creux.offset_left = -94
	creux.offset_right = -14
	creux.offset_top = haut
	creux.offset_bottom = haut + 8
	couche.add_child(creux)

	var part := ColorRect.new()
	part.color = plein
	part.anchor_right = 1.0
	part.anchor_bottom = 1.0
	creux.add_child(part)
	return part


func _jauger(reste: int, sur: int) -> void:
	_ui.jauges(reste, sur, _energie, ENERGIE_MAX)


## Le personnage se tourne vers celui qui l'aborde.
##
## Parler au dos de quelqu'un est ce qui trahissait le plus que ces gens sont
## des décors posés : le Roi répondait à Wellan sans le regarder. Il suffit de
## reprendre la rangée de sa planche selon l'axe qui les sépare — celui des deux
## écarts qui domine, comme pour la marche.
##
## Il garde ensuite cette orientation. Un personnage qui reprendrait sa pose
## d'origine sitôt la conversation finie aurait l'air de se détourner.
func _tourner_vers_moi(id: String) -> void:
	if id.begins_with("objet:"):
		return
	if not _habitants.has(id):
		return
	var corps: Node2D = _habitants[id]
	var vue: Sprite2D = null
	for enfant in corps.get_children():
		if enfant is Sprite2D:
			vue = enfant
			break
	if vue == null or not (vue.texture is AtlasTexture):
		return

	var ecart := _wellan.global_position - corps.global_position
	var sens := "sud"
	if absf(ecart.x) > absf(ecart.y):
		sens = "est" if ecart.x > 0.0 else "ouest"
	else:
		sens = "sud" if ecart.y > 0.0 else "nord"

	var region: AtlasTexture = vue.texture
	region.region = Rect2(region.region.position.x, RANGEE[sens] * SPRITE, SPRITE, SPRITE)


## Ce que dit un personnage.
##
## La scène en cours d'abord : si le chapitre lui a écrit des répliques pour
## cette étape, ce sont celles-là. Sa fiche à défaut — de sorte qu'aucun
## personnage ne soit jamais muet, même ajouté à la dernière minute et sans une
## ligne écrite pour lui.
func _repliques(id: String) -> Array:
	var source := _repliques_de(id)
	if not source.is_empty():
		_cle_courante = str(source["cle"])
		var pages := []
		for ligne in source["lignes"]:
			var qui := str(ligne.get("qui", ""))
			var dit := str(ligne.get("dit", ""))
			if qui == "recit":
				pages.append({ "genre": "recit", "texte": dit })
			else:
				var nom := str(_monde["personnages"].get(qui, {}).get("nom", qui))
				pages.append({ "genre": "parole", "qui": qui, "nom": nom, "texte": dit,
					"humeur": str(ligne.get("humeur", "")) })
		return pages
	return _fiche_en_repliques(id)


## Un personnage n'a rien à dire hors de ce que la scène lui écrit.
##
## Le pis-aller récitait sa fiche du Codex — son rôle, puis la liste de ses
## liens : « Wellan — Frère d'armes et confident ; Wanda — Épouse, mère de ses
## enfants ». C'est de la documentation, pas du jeu, et elle a déjà un endroit
## où vivre.
##
## Un personnage sans réplique écrite est donc muet, et l'on ne peut pas
## l'aborder : ni bulle, ni invite, ni cadre vide.
func _fiche_en_repliques(_id: String) -> Array:
	return []


func _afficher() -> void:
	if _page >= _pages.size():
		_ouverte = false
		_ui.fermer_dialogue()
		_ui.invite(_proche != "")
		# On ne compte l'échange que s'il a été mené jusqu'au bout : entamer une
		# conversation et s'en aller ne fait pas avancer le chapitre.
		if _interlocuteur != "":
			_parles[_interlocuteur] = true
			if _cle_courante != "":
				_entendus[_cle_courante] = true
				_cle_courante = ""
			var qui := _interlocuteur
			_interlocuteur = ""
			_avancer_si_possible()
			_rafraichir_les_bulles()
			# Le présent vient après la phrase, jamais pendant : on écoute
			# d'abord ce qu'il a à en dire, on l'accepte ensuite.
			if _offres.has(qui):
				_ouvrir_le_butin("personne:%s" % qui)
		elif _butin_en_attente != "":
			# La description est lue : le coffre s'ouvre maintenant, et non
			# pendant qu'on lisait.
			var quel := _butin_en_attente
			_butin_en_attente = ""
			_ouvrir_le_butin(quel)
		elif _cloture_dite and not _ui.acheve_visible():
			# La clôture vient de se terminer : l'écran de fin peut paraître.
			_achever_le_chapitre()
		return
	var page: Dictionary = _pages[_page]
	_sons.jouer("parole")
	if str(page.get("genre", "parole")) == "recit":
		_ui.recit(str(page.get("texte", "")))
	else:
		_ui.parole(str(page.get("nom", "")), str(page.get("texte", "")),
			_visage_de(str(page.get("qui", "")), str(page.get("humeur", ""))))


## Récite une suite de descriptions.
##
## Ni parole ni personnage : c'est la voix qui pose un chapitre et celle qui le
## referme. Elle emprunte le même mécanisme de pages, avec le genre « recit »,
## donc le bandeau large et l'italique — ce que le joueur lit, non ce qu'on lui
## dit.
func _reciter(lignes: Array) -> void:
	if lignes.is_empty():
		return
	_pages = []
	for l in lignes:
		_pages.append({ "genre": "recit", "texte": str(l) })
	_page = 0
	_interlocuteur = ""
	_ouverte = true
	_ui.invite(false)
	_afficher()


## Montre le portrait de qui parle, et décale le texte pour lui faire place.
func _visage_de(id: String, humeur := "") -> String:
	var fiche: Dictionary = _monde["personnages"].get(id, {})
	var visage = fiche.get("portrait")

	# L'humeur ne s'impose que si le visage la connaît : une réplique peut en
	# demander une qu'on n'a pas encore dessinée, et il vaut mieux un visage
	# neutre qu'un cadre vide.
	if humeur != "" and visage != null:
		var connues: Array = fiche.get("humeurs", [])
		if connues.has(humeur):
			visage = "portrait-%s-%s.png" % [id, humeur]

	return "" if visage == null else str(visage)


const CHOIX_PAUSE := ["Reprendre", "Carte", "Codex", "Sac", "Chapitres", "Commandes", "Sauvegarder", "Écran-titre"]

## Les deux catégories du sac, qui ne se mélangent pas.
const CATEGORIES_SAC := ["Objets", "Équipements"]

const NOMS_STATS := {
	"force": "Force", "vitesse": "Vitesse", "vitalite": "Vitalité",
	"sagesse": "Sagesse", "defense": "Défense",
}

## Ce que montre l'écran des commandes.
##
## Les touches y sont écrites pour être lues, non relevées dans la table
## d'entrées : `ui_accept` y porte Espace, Entrée et Entrée du pavé, et une aide
## qui les énumère toutes les trois n'aide plus. En revanche `action` nomme
## l'entrée réelle, et le banc vérifie qu'elle existe et porte au moins une
## touche — ce qui attrape la seule dérive qui compte, celle d'une commande
## renommée ou disparue.
const COMMANDES := [
	{ "touches": "Flèches   ·   W A S D", "action": "ui_up", "quoi": "Se déplacer" },
	{ "touches": "P", "action": "courir", "quoi": "Courir" },
	{ "touches": "Espace", "action": "ui_accept", "quoi": "Parler, examiner, franchir une porte" },
	{ "touches": "J", "action": "frapper", "quoi": "L'épée" },
	{ "touches": "K", "action": "lancer", "quoi": "Le feu de Theandras" },
	{ "touches": "Échap", "action": "pause", "quoi": "Le menu, la carte, le Codex, le sac" },
	{ "touches": "Entrée", "action": "suivant", "quoi": "Le chapitre suivant, une fois achevé" },
]

func _dessiner_la_pause(mot := "") -> void:
	_ui.pause(_en_pause, _choix_pause, CHOIX_PAUSE, mot)


func _basculer_la_pause() -> void:
	_en_pause = not _en_pause
	_choix_pause = 0
	_ui.pause(_en_pause)
	# La musique s'arrête avec le jeu. Les bruitages, eux, sont déjà finis.
	_sons.suspendre(_en_pause)
	if _en_pause:
		_wellan.velocity = Vector2.ZERO
		_dessiner_la_pause()


## Ce que fait l'entrée choisie.
##
## Reconnue par son nom et non par son rang : intercaler « Codex » en deuxième
## position aurait fait de « Sauvegarder » un retour à l'écran-titre, et rien
## dans le code ne l'aurait signalé.
func _choisir_dans_la_pause() -> void:
	_sons.jouer("menu-choix")
	match CHOIX_PAUSE[_choix_pause]:
		"Reprendre":
			_basculer_la_pause()
		"Codex":
			_ouvrir_le_codex()
		"Sac":
			_ouvrir_le_sac()
		"Carte":
			_ouvrir_la_carte()
		"Chapitres":
			_ouvrir_les_chapitres()
		"Commandes":
			_ouvrir_les_commandes(true)
		"Sauvegarder":
			_noter(_chapitre)
			_dessiner_la_pause("Partie notée.")
		"Écran-titre":
			get_tree().change_scene_to_file("res://titre.tscn")


## Le Codex se consulte depuis la pause, et y revient.
##
## Il est reconstruit à chaque ouverture plutôt que tenu à jour : la partie est
## la seule à savoir qui l'on a rencontré, et une copie en mémoire finirait par
## en dire moins qu'elle.
func _ouvrir_le_codex() -> void:
	_fiches_codex = _fiches_du_codex()
	_choix_codex = 0
	_au_codex = true
	_ui.pause(false)
	_ui.codex(true, _fiches_codex, _choix_codex, _monde["personnages"].size())


## L'écran des commandes, appelé au départ ou depuis le menu.
func _ouvrir_les_commandes(depuis_pause: bool) -> void:
	_commandes_depuis_pause = depuis_pause
	_aux_commandes = true
	# Le jeu s'arrête derrière : un écran qu'on lit pendant que Wellan continue
	# de marcher n'est pas un écran, c'est un obstacle.
	_en_pause = true
	_ui.pause(false)
	_ui.commandes(true, COMMANDES)


func _fermer_les_commandes() -> void:
	_aux_commandes = false
	_ui.commandes(false)
	# On revient d'où l'on venait : au menu si c'est lui qui a ouvert, au jeu
	# sinon. Rendre toujours le menu ouvrirait une pause que personne n'a
	# demandée à la première partie.
	if _commandes_depuis_pause:
		_dessiner_la_pause()
	else:
		_en_pause = false
	_commandes_depuis_pause = false


## Ce qu'un meuble contient encore.
##
## Le sac fait foi : une pièce déjà prise ne reparaît pas, et le coffre reste
## ouvert et vide plutôt que de se refermer sur rien.
func _butin_de(cle: String) -> Array:
	var reste := []
	var sac: Array = Partie.sac()
	for prise in _contenu_de(cle):
		if not sac.has(str((prise as Dictionary)["id"])):
			reste.append(prise)
	return reste


## Ce qu'une clé de butin désigne — un meuble ouvert, ou quelqu'un qui donne.
##
## Les deux passent par la même fenêtre : un présent se regarde comme un coffre
## se fouille, et l'on veut la description et le barème avant de tendre la main.
func _contenu_de(cle: String) -> Array:
	if cle.begins_with("personne:"):
		var don = _offres.get(cle.substr(9), null)
		return [] if don == null else [don]
	return (_objets.get(cle, {}) as Dictionary).get("contient", [])


func _ouvrir_le_butin(cle: String) -> void:
	_contenu_butin = _butin_de(cle)
	if _contenu_butin.is_empty():
		return
	_au_butin = cle
	_choix_butin = 0
	_en_pause = true
	_rafraichir_le_butin()


func _fermer_le_butin() -> void:
	_au_butin = ""
	_contenu_butin = []
	_ui.butin(false)
	_en_pause = false


func _rafraichir_le_butin() -> void:
	_choix_butin = clampi(_choix_butin, 0, maxi(_contenu_butin.size() - 1, 0))
	var pieces := []
	for prise in _contenu_butin:
		var p: Dictionary = prise
		var fiche: Dictionary = (_monde.get("prises", {}) as Dictionary).get(str(p["id"]), {})
		pieces.append({
			"nom": str(p.get("nom", "")),
			"image": int(fiche.get("image", -1)),
			"texte": p.get("texte", []),
			"emplacement": str(p.get("emplacement", "")),
			"bonus": _bonus_en_clair(p.get("bonus", {})),
		})
	_ui.butin(true, {
		"coffre": _titre_du_butin(),
		"pieces": pieces, "choix": _choix_butin,
	})


## Qui ou quoi offre ce qu'on regarde.
func _titre_du_butin() -> String:
	if _au_butin.begins_with("personne:"):
		var fiche: Dictionary = _monde["personnages"].get(_au_butin.substr(9), {})
		return "%s vous donne" % str(fiche.get("nom", _au_butin.substr(9)))
	return str((_objets.get(_au_butin, {}) as Dictionary).get("nom", ""))


## Les bonus d'une pièce, lisibles.
##
## « force: 5 » ne dit rien à personne ; « Force +5 » se lit d'un coup. La
## conversion appartient au jeu, qui sait ce que chaque statistique commande —
## l'interface se contente d'afficher la phrase.
func _bonus_en_clair(bonus: Dictionary) -> String:
	var bouts := PackedStringArray()
	for cle in ["force", "vitesse", "vitalite", "sagesse", "defense"]:
		if not bonus.has(cle):
			continue
		var v := int(bonus[cle])
		bouts.append("%s %s%d" % [str(NOMS_STATS[cle]), "+" if v >= 0 else "−", absi(v)])
	return ", ".join(bouts)


## Prendre la pièce visée.
func _prendre_du_butin() -> void:
	if _contenu_butin.is_empty():
		return
	var prise: Dictionary = _contenu_butin[_choix_butin]
	if Partie.prendre(str(prise["id"])):
		_ui.avis("Sac  ·  %s" % str(prise.get("nom", "")))
		_sons.jouer("codex-ajout")
		_recalculer_les_stats()
	_contenu_butin.remove_at(_choix_butin)
	if _contenu_butin.is_empty():
		_fermer_le_butin()
		return
	_rafraichir_le_butin()


## La carte du continent, d'où l'on voyage.
func _ouvrir_la_carte() -> void:
	_escales = _escales_du_monde()
	_choix_carte = 0
	for i in _escales.size():
		if bool((_escales[i] as Dictionary).get("ici", false)):
			_choix_carte = i
	_a_la_carte = true
	_ui.pause(false)
	_ui.carte(true, { "escales": _escales, "choix": _choix_carte })


func _fermer_la_carte() -> void:
	_a_la_carte = false
	_ui.carte(false)
	_dessiner_la_pause()


## Les escales, avec leur place en pixels sur la carte affichée.
##
## La conversion se fait ici et non dans l'interface : la carte est dessinée à
## trois cent vingt sur cent quatre-vingts et l'écran en fait le double, et ce
## facteur appartient au jeu, qui sait à quelle taille il rend.
func _escales_du_monde() -> Array:
	var carte: Dictionary = _monde.get("carte", {})
	var cel := float(carte.get("cellule", 5))
	var facteur := 640.0 / maxf(float(carte.get("largeur", 320)), 1.0)
	var ici := str(_salle.get("lieu", ""))
	var attend := _lieu_du_chapitre()

	var liste := []
	for e in carte.get("escales", []):
		var lieu := str(e["lieu"])
		var role := str((_monde.get("lieux", {}) as Dictionary).get(lieu, {}).get("role", ""))
		liste.append({
			"lieu": lieu, "nom": str(e["nom"]), "salle": str(e["salle"]),
			"px": (float(e["x"]) * cel + cel / 2.0) * facteur,
			"py": (float(e["y"]) * cel + cel / 2.0) * facteur,
			# Assez court pour tenir sur une ligne du bandeau : au-delà, le rappel
			# des touches se trouvait poussé hors du cadre.
			"quoi": role.substr(0, 68) + ("…" if role.length() > 68 else ""),
			"ici": lieu == ici,
			"chapitre": lieu == attend,
			"atteint": true,
		})
	return liste


## Choisit l'escale la plus proche dans la direction pressée.
##
## Une liste qu'on parcourt de haut en bas ne convient pas à une carte : ce
## qu'on vise est un endroit, non un rang. On prend donc la plus proche dans le
## sens demandé, ce qui rend le déplacement conforme à ce qu'on voit.
func _viser_sur_la_carte(sens: Vector2) -> void:
	if _escales.is_empty():
		return
	var de: Dictionary = _escales[_choix_carte]
	var origine := Vector2(float(de["px"]), float(de["py"]))
	var meilleur := -1
	var court := INF
	for i in _escales.size():
		if i == _choix_carte:
			continue
		var e: Dictionary = _escales[i]
		var ecart := Vector2(float(e["px"]), float(e["py"])) - origine
		if ecart.normalized().dot(sens) < 0.5:
			continue
		var d := ecart.length()
		if d < court:
			court = d
			meilleur = i
	if meilleur < 0:
		return
	_choix_carte = meilleur
	_sons.jouer("menu-deplace")
	_ui.carte(true, { "escales": _escales, "choix": _choix_carte })


## S'y rendre.
##
## Si le chapitre en cours attend dans ce lieu, on dépose directement dans sa
## salle plutôt qu'à l'entrée : le Château compte six pièces, et traverser cinq
## d'entre elles après chaque voyage serait une corvée, non une exploration.
func _voyager() -> void:
	if _escales.is_empty():
		return
	var e: Dictionary = _escales[_choix_carte]
	if bool(e.get("ici", false)):
		return
	var vers := str(e["salle"])
	if bool(e.get("chapitre", false)):
		vers = str(_scene.get("salle", ""))
	_sons.jouer("menu-choix")
	_a_la_carte = false
	_ui.carte(false)
	_en_pause = false
	_changer_de_salle(vers, Vector2i(-1, -1))


## Les chapitres déjà ouverts, pour les rejouer.
##
## On ne montre pas seulement ceux qu'on peut reprendre : la campagne entière
## est là, et ce qui n'a pas encore été atteint s'affiche éteint. Un recueil
## sert autant à montrer ce qui manque qu'à ranger ce qu'on a — c'est déjà la
## règle du Codex, et elle vaut ici.
func _ouvrir_les_chapitres() -> void:
	_liste_chapitres = _chapitres_de_la_campagne()
	_choix_chapitre = 0
	# On s'ouvre sur le chapitre en cours plutôt qu'en tête de liste : c'est
	# celui dont on vient, donc celui qu'on cherche des yeux.
	for i in _liste_chapitres.size():
		if bool((_liste_chapitres[i] as Dictionary).get("courant", false)):
			_choix_chapitre = i
	_aux_chapitres = true
	_ui.pause(false)
	_ui.chapitres(true, { "liste": _liste_chapitres, "choix": _choix_chapitre })


func _fermer_les_chapitres() -> void:
	_aux_chapitres = false
	_ui.chapitres(false)
	_dessiner_la_pause()


func _chapitres_de_la_campagne() -> Array:
	var joues: Array = Partie.joues()
	var liste := []
	for id in Partie.campagne():
		var scene := _lire(DONNEES + "scenes/%s.json" % str(id))
		liste.append({
			"id": str(id),
			"rang": Partie.rang(str(id)),
			"titre": str(scene.get("titre", id)),
			"source": str(scene.get("source", "")),
			"avertissement": str(scene.get("avertissement", "")),
			"joue": joues.has(str(id)),
			"courant": str(id) == _chapitre,
		})
	return liste


## Rejoue le chapitre choisi.
##
## La scène se recharge, et `Partie.rejoue` dit à la suivante quoi ouvrir. Rien
## n'est noté : on ressort du chapitre rejoué exactement là où l'on était.
func _rejouer_le_choisi() -> void:
	if _liste_chapitres.is_empty():
		return
	var choisi: Dictionary = _liste_chapitres[_choix_chapitre]
	if not bool(choisi.get("joue", false)):
		return
	_sons.jouer("menu-choix")
	Partie.rejoue = str(choisi["id"])
	get_tree().reload_current_scene()


## Le sac se consulte depuis la pause, et y revient.
##
## Reconstruit à chaque ouverture, comme le Codex : la partie est la seule à
## savoir ce qu'on porte, et une copie en mémoire finirait par en dire moins.
func _ouvrir_le_sac() -> void:
	_choix_sac = 0
	_au_sac = true
	_ui.pause(false)
	_rafraichir_le_sac()


func _fermer_le_sac() -> void:
	_au_sac = false
	_ui.sac(false)
	_dessiner_la_pause()


## Ce que le sac montre, dans la catégorie ouverte.
##
## Les deux catégories ne se mélangent jamais : un équipement se porte, un objet
## se garde, et les confondre dans une liste où l'on presse Espace ferait
## « équiper » une couverture. La production refuse d'ailleurs un objet qui
## porterait un emplacement, et un équipement qui n'en porterait pas.
func _contenu_du_sac() -> Array:
	var liste := []
	var catalogue: Dictionary = _monde.get("prises", {})
	var porte: Dictionary = Partie.equipe()
	var veut := "equipement" if _categorie_sac == 1 else "objet"
	for id in Partie.sac():
		var fiche: Dictionary = catalogue.get(str(id), {})
		if fiche.is_empty() or str(fiche.get("categorie", "objet")) != veut:
			continue
		var emplacement := str(fiche.get("emplacement", ""))
		liste.append({
			"id": str(id),
			"nom": str(fiche.get("nom", id)),
			"ou": "Trouvé : %s" % str(fiche.get("ou", "")),
			"texte": fiche.get("texte", []),
			"image": int(fiche.get("image", -1)),
			"emplacement": emplacement,
			"porte": emplacement != "" and str(porte.get(emplacement, "")) == str(id),
		})
	return liste


## Ce que vaudraient les statistiques si l'on portait cette pièce.
func _apercu_de(choisi: Dictionary) -> Dictionary:
	if _categorie_sac != 1 or choisi.is_empty() or bool(choisi.get("porte", false)):
		return {}
	var porte: Dictionary = Partie.equipe().duplicate()
	porte[str(choisi["emplacement"])] = str(choisi["id"])
	return _stats_depuis(porte)


## Les statistiques mises en lignes, avec ce que chacune commande.
##
## Le nombre nu ne dit rien — « Vitesse 8 » n'apprend rien à personne. C'est ce
## qu'il produit qui se lit : quatre-vingts pixels par seconde, vingt-quatre
## points de vie. Le jeu fait la conversion, l'interface se contente d'afficher.
func _lignes_de_stats(apercu: Dictionary) -> Array:
	var lignes := []
	for cle in ["force", "vitesse", "vitalite", "sagesse", "defense"]:
		var a := int(_stats.get(cle, 0))
		var b := int(apercu.get(cle, a)) if not apercu.is_empty() else a
		lignes.append({
			"nom": str(NOMS_STATS[cle]), "valeur": a, "apres": b,
			"effet": _effet_de(str(cle), b),
		})
	return lignes


func _effet_de(cle: String, v: int) -> String:
	match cle:
		"force": return "épée %d" % (1 + int(v - BASE["force"]) / FORCE_PAR_DEGAT)
		"vitesse": return "%d px/s" % int(maxf(1.0, float(v)) * PIXELS_PAR_VITESSE)
		"vitalite": return "%d points de vie" % (v * VIE_PAR_VITALITE)
		"sagesse": return "sort %d" % v
		_: return "−%d par coup" % (v / DEFENSE_PAR_POINT)


func _rafraichir_le_sac() -> void:
	_contenu_sac = _contenu_du_sac()
	_choix_sac = clampi(_choix_sac, 0, maxi(_contenu_sac.size() - 1, 0))
	var choisi: Dictionary = _contenu_sac[_choix_sac] if not _contenu_sac.is_empty() else {}
	# Ce que Wellan porte, emplacement par emplacement : c'est ce que la vue
	# d'équipement dispose autour de lui.
	var porte := {}
	var catalogue: Dictionary = _monde.get("prises", {})
	var equipe: Dictionary = Partie.equipe()
	for e in _monde.get("emplacements", []):
		var id := str(equipe.get(str(e), ""))
		var fiche: Dictionary = catalogue.get(id, {})
		porte[str(e)] = {
			"nom": str(fiche.get("nom", "")),
			"image": int(fiche.get("image", -1)),
			"vide": fiche.is_empty(),
		}

	_ui.sac(true, {
		"categories": CATEGORIES_SAC, "categorie": _categorie_sac,
		"liste": _contenu_sac, "choix": _choix_sac,
		"stats": _lignes_de_stats(_apercu_de(choisi)),
		"equipable": _categorie_sac == 1,
		"emplacements": _monde.get("emplacements", []),
		"porte": porte,
		"vise": str(choisi.get("emplacement", "")),
		"sprite": str((_monde["personnages"].get("wellan", {}) as Dictionary).get("planche", "")),
	})


## Porter la pièce choisie — ou la reposer si on la porte déjà.
func _equiper_le_choisi() -> void:
	if _categorie_sac != 1 or _contenu_sac.is_empty():
		return
	var choisi: Dictionary = _contenu_sac[_choix_sac]
	var emplacement := str(choisi["emplacement"])
	# Le même geste met et retire : un emplacement ne tient qu'une pièce, et
	# demander une seconde touche pour déséquiper serait une règle de plus à
	# retenir pour rien.
	Partie.equiper(emplacement, "" if bool(choisi["porte"]) else str(choisi["id"]))
	_recalculer_les_stats()
	_sons.jouer("menu-choix")
	_rafraichir_le_sac()


func _fermer_le_codex() -> void:
	_au_codex = false
	_ui.codex(false)
	_dessiner_la_pause()


## Les rencontres, rangées par leur numéro de Codex.
##
## Rangées, non pas dans l'ordre où on les a croisées : un recueil se feuillette
## par son classement, et c'est ce numéro qui permet de voir ce qui manque.
func _fiches_du_codex() -> Array:
	var fiches := []
	for id in Partie.rencontres():
		var fiche: Dictionary = _monde["personnages"].get(str(id), {})
		if fiche.is_empty():
			continue
		var visage = fiche.get("portrait")
		fiches.append({
			"rang": int(fiche.get("rang", 0)),
			"nom": str(fiche.get("nom", id)),
			"role": str(fiche.get("role", "")),
			"portrait": "" if visage == null else str(visage),
			"teinte": str(fiche.get("teinte", "#f0d174")),
			"tomes": fiche.get("tomes", []),
			"liens": fiche.get("liens", []),
		})
	fiches.sort_custom(func(a, b): return a["rang"] < b["rang"])
	return fiches


## Inscrit au Codex celui à qui l'on adresse la parole.
##
## Dès l'abord, et non à la fin de l'échange comme `_parles` : on a bel et bien
## rencontré quelqu'un même si l'on s'éloigne au milieu de sa phrase. Le
## chapitre, lui, n'avance toujours qu'au bout de la conversation.
func _rencontrer(id: String) -> void:
	if not _monde["personnages"].has(id):
		return
	# `rencontrer` rend vrai la première fois seulement : c'est ce qui permet de
	# ne l'annoncer qu'une fois. Une collection qui se remplit sans le dire ne
	# se sait pas — on n'ouvre pas un recueil pour vérifier s'il a changé.
	if Partie.rencontrer(id):
		var fiche: Dictionary = _monde["personnages"][id]
		_ui.avis("Codex  ·  %s" % str(fiche.get("nom", id)))
		_sons.jouer("codex-ajout")


## Qui a quelque chose à dire qu'on n'a pas encore entendu.
##
## Seule la parole écrite par la scène compte. Une fiche du Codex se lit comme
## une description et reste disponible indéfiniment : la signaler mettrait une
## bulle sur les trois cent soixante-cinq personnages du monde, ce qui ne
## voudrait plus rien dire.
func _a_dire(id: String) -> bool:
	if id.begins_with("objet:"):
		return false
	var source := _repliques_de(id)
	if source.is_empty():
		return false
	# La bulle marque ce qu'on n'a pas entendu, ici comme après la clôture.
	return not _entendus.has(str(source["cle"]))


func _rafraichir_les_bulles() -> void:
	for id in _habitants:
		var doit := _a_dire(str(id))
		if doit and not _bulles.has(id):
			var corps: Node2D = _habitants[id]
			var bulle := Sprite2D.new()
			bulle.texture = load(DONNEES + "bulle.png")
			bulle.position = Vector2(0, -38)
			corps.add_child(bulle)
			_bulles[id] = bulle
		elif not doit and _bulles.has(id):
			if is_instance_valid(_bulles[id]):
				_bulles[id].queue_free()
			_bulles.erase(id)

	# Ceux qui ont quitté la salle emportent la leur.
	for id in _bulles.keys():
		if not _habitants.has(id):
			if is_instance_valid(_bulles[id]):
				_bulles[id].queue_free()
			_bulles.erase(id)


func _unhandled_input(evenement: InputEvent) -> void:
	# Les commandes couvrent tout, le carton du chapitre compris : elles se
	# ferment avant que quoi que ce soit d'autre écoute.
	if _aux_commandes:
		if evenement.is_action_pressed("ui_accept") or evenement.is_action_pressed("pause") \
			or evenement.is_action_pressed("ui_cancel"):
			_sons.jouer("menu-choix")
			_fermer_les_commandes()
		return

	if _au_butin != "":
		if evenement.is_action_pressed("pause") or evenement.is_action_pressed("ui_cancel"):
			_fermer_le_butin()
		elif evenement.is_action_pressed("ui_accept"):
			_prendre_du_butin()
		elif evenement.is_action_pressed("ui_right") and not _contenu_butin.is_empty():
			_choix_butin = (_choix_butin + 1) % _contenu_butin.size()
			_sons.jouer("menu-deplace")
			_rafraichir_le_butin()
		elif evenement.is_action_pressed("ui_left") and not _contenu_butin.is_empty():
			_choix_butin = (_choix_butin + _contenu_butin.size() - 1) % _contenu_butin.size()
			_sons.jouer("menu-deplace")
			_rafraichir_le_butin()
		return

	if _a_la_carte:
		if evenement.is_action_pressed("pause") or evenement.is_action_pressed("ui_cancel"):
			_fermer_la_carte()
		elif evenement.is_action_pressed("ui_accept"):
			_voyager()
		elif evenement.is_action_pressed("ui_left"):
			_viser_sur_la_carte(Vector2.LEFT)
		elif evenement.is_action_pressed("ui_right"):
			_viser_sur_la_carte(Vector2.RIGHT)
		elif evenement.is_action_pressed("ui_up"):
			_viser_sur_la_carte(Vector2.UP)
		elif evenement.is_action_pressed("ui_down"):
			_viser_sur_la_carte(Vector2.DOWN)
		return

	if _aux_chapitres:
		if evenement.is_action_pressed("pause") or evenement.is_action_pressed("ui_cancel"):
			_fermer_les_chapitres()
		elif evenement.is_action_pressed("ui_accept"):
			_rejouer_le_choisi()
		elif evenement.is_action_pressed("ui_down") and not _liste_chapitres.is_empty():
			_choix_chapitre = (_choix_chapitre + 1) % _liste_chapitres.size()
			_sons.jouer("menu-deplace")
			_ui.chapitres(true, { "liste": _liste_chapitres, "choix": _choix_chapitre })
		elif evenement.is_action_pressed("ui_up") and not _liste_chapitres.is_empty():
			_choix_chapitre = (_choix_chapitre + _liste_chapitres.size() - 1) % _liste_chapitres.size()
			_sons.jouer("menu-deplace")
			_ui.chapitres(true, { "liste": _liste_chapitres, "choix": _choix_chapitre })
		return

	if _au_sac:
		if evenement.is_action_pressed("pause") or evenement.is_action_pressed("ui_cancel"):
			_fermer_le_sac()
		elif evenement.is_action_pressed("ui_left") or evenement.is_action_pressed("ui_right"):
			_categorie_sac = 1 - _categorie_sac
			_choix_sac = 0
			_sons.jouer("menu-deplace")
			_rafraichir_le_sac()
		elif evenement.is_action_pressed("ui_accept"):
			_equiper_le_choisi()
		elif evenement.is_action_pressed("ui_down") and not _contenu_sac.is_empty():
			_choix_sac = (_choix_sac + 1) % _contenu_sac.size()
			_sons.jouer("menu-deplace")
			_rafraichir_le_sac()
		elif evenement.is_action_pressed("ui_up") and not _contenu_sac.is_empty():
			_choix_sac = (_choix_sac + _contenu_sac.size() - 1) % _contenu_sac.size()
			_sons.jouer("menu-deplace")
			_rafraichir_le_sac()
		return

	# Le Codex passe même avant la pause : Échap doit refermer le recueil et
	# rendre le menu, non quitter les deux d'un coup.
	if _au_codex:
		if evenement.is_action_pressed("pause") or evenement.is_action_pressed("ui_cancel"):
			_fermer_le_codex()
		elif evenement.is_action_pressed("ui_down") and not _fiches_codex.is_empty():
			_choix_codex = (_choix_codex + 1) % _fiches_codex.size()
			_sons.jouer("menu-deplace")
			_ui.codex(true, _fiches_codex, _choix_codex, _monde["personnages"].size())
		elif evenement.is_action_pressed("ui_up") and not _fiches_codex.is_empty():
			_choix_codex = (_choix_codex + _fiches_codex.size() - 1) % _fiches_codex.size()
			_sons.jouer("menu-deplace")
			_ui.codex(true, _fiches_codex, _choix_codex, _monde["personnages"].size())
		return

	# La pause passe avant le reste : on doit pouvoir s'arrêter au milieu d'une
	# réplique comme au milieu d'une mêlée.
	if evenement.is_action_pressed("pause") and not _ui.carton_visible() and not _ui.acheve_visible():
		_basculer_la_pause()
		return
	if _en_pause:
		if evenement.is_action_pressed("ui_down"):
			_choix_pause = (_choix_pause + 1) % CHOIX_PAUSE.size()
			_sons.jouer("menu-deplace")
			_dessiner_la_pause()
		elif evenement.is_action_pressed("ui_up"):
			_choix_pause = (_choix_pause + CHOIX_PAUSE.size() - 1) % CHOIX_PAUSE.size()
			_sons.jouer("menu-deplace")
			_dessiner_la_pause()
		elif evenement.is_action_pressed("ui_accept"):
			_choisir_dans_la_pause()
		return

	if _ui.carton_visible():
		if evenement.is_action_pressed("ui_accept"):
			_ui.fermer_carton()
			_reciter(_scene.get("ouverture", []))
		return
	# Entrée appelle le chapitre suivant, à tout moment une fois le mot affiché.
	# La progression est déjà notée : recharger la scène l'ouvre sans qu'on ait
	# à transporter d'état.
	if _ui.acheve_visible() and evenement.is_action_pressed("suivant"):
		get_tree().reload_current_scene()
		return
	if evenement.is_action_pressed("frapper") and not _ouverte and not _vaincu:
		_frapper()
		return
	if evenement.is_action_pressed("lancer") and not _ouverte and not _vaincu:
		_lancer()
		return
	if not evenement.is_action_pressed("ui_accept"):
		return
	if _vaincu:
		_reprendre()
		return
	if _ouverte:
		_page += 1
		_afficher()
	elif _proche.begins_with("passage:"):
		_franchir(_proche)
		return
	elif _proche.begins_with("objet:"):
		var chose: Dictionary = _objets.get(_proche, {})
		var lignes: Array = (chose.get("texte", []) as Array).duplicate()
		var nom := str(chose.get("nom", ""))
		if nom != "":
			lignes = [nom] + lignes

		# Le meuble ne se vide plus tout seul.
		#
		# On lisait sa description et tout son contenu tombait dans le sac dans
		# la même phrase — on ne voyait jamais ce qu'on ramassait. La description
		# d'abord, donc, puis le coffre s'ouvre et c'est le joueur qui tend la
		# main, pièce par pièce.
		_butin_en_attente = _proche if not _butin_de(_proche).is_empty() else ""
		_reciter(lignes)
		return
	elif _proche != "":
		_interlocuteur = _proche
		_rencontrer(_proche)
		_pages = _repliques(_proche)
		_page = 0
		_ouverte = true
		_ui.invite(false)
		_tourner_vers_moi(_proche)
		_afficher()


## Le coup d'épée.
##
## On interroge l'espace plutôt que de poser une zone le temps d'une image :
## un nœud créé puis détruit à chaque coup laisse la détection à la merci de
## l'ordre des images, et l'on frappe dans le vide une fois sur trois.
func _frapper() -> void:
	var maintenant := Time.get_ticks_msec() / 1000.0
	if maintenant < _prochain_coup:
		return
	_prochain_coup = maintenant + REPOS_EPEE

	var devant := _wellan.global_position + _vers(_direction) * (PORTEE_EPEE - LARGEUR_COUP)
	var forme := CircleShape2D.new()
	forme.radius = LARGEUR_COUP

	var demande := PhysicsShapeQueryParameters2D.new()
	demande.shape = forme
	demande.transform = Transform2D(0.0, devant)
	demande.collide_with_bodies = true
	# Le geste s'entend même dans le vide : c'est ce qui apprend la portée. Le
	# choc, lui, ne s'entend que s'il a porté — deux sons, deux informations.
	_sons.jouer("epee")
	var porte := false
	for touche in get_world_2d().direct_space_state.intersect_shape(demande, 8):
		var qui = touche.get("collider")
		if qui is Combattant and qui != _wellan:
			if qui.encaisser(_degats_epee(), "fer"):
				porte = true
	if porte:
		_sons.jouer("fer-touche")

	# L'arc part du personnage, non de la zone frappée : c'est le geste qu'on
	# montre, et il doit sortir de la main.
	_jouer_effet("taillade.png", 3, TAILLADE, _wellan.global_position + Vector2(0, -10),
		QUART.get(_direction, 0.0), REPOS_EPEE / 4.0, 8.0)


## Le feu de Theandras, déesse protectrice des Chevaliers.
func _lancer() -> void:
	if _energie < COUT_DU_SORT:
		return
	_energie -= COUT_DU_SORT
	_sons.jouer("sort")

	var porteur := Node2D.new()
	porteur.position = _wellan.global_position + Vector2(0, -10)
	add_child(porteur)

	# La braise bat en boucle tant que le trait vole : elle ne s'éteint pas au
	# bout de quatre images, elle recommence.
	var vue := Sprite2D.new()
	var region := AtlasTexture.new()
	region.atlas = load(DONNEES + "feu.png")
	region.region = Rect2(0, 0, FEU_COTE, FEU_COTE)
	vue.texture = region
	porteur.add_child(vue)

	var battement := Timer.new()
	battement.wait_time = 0.07
	porteur.add_child(battement)
	# Même raison qu'au-dessus : capture par valeur, donc un dictionnaire.
	var braise := { "image": 0 }
	battement.timeout.connect(func() -> void:
		braise["image"] = (int(braise["image"]) + 1) % 4
		region.region = Rect2(int(braise["image"]) * FEU_COTE, 0, FEU_COTE, FEU_COTE))
	battement.start()

	_traits.append({ "noeud": porteur, "sens": _vers(_direction), "reste": PORTEE_SORT })


func _vers(sens: String) -> Vector2:
	match sens:
		"nord": return Vector2.UP
		"sud": return Vector2.DOWN
		"ouest": return Vector2.LEFT
		_: return Vector2.RIGHT


## L'angle de chaque direction, pour faire pivoter un effet dessiné vers l'est.
##
## Des quarts de tour seulement : à 90 degrés une image de pixel art tourne sans
## perdre un pixel, ce qui ne serait pas vrai d'un angle quelconque.
const QUART := { "est": 0.0, "sud": 90.0, "ouest": 180.0, "nord": 270.0 }


## Joue une petite animation puis s'efface.
##
## Les effets sont des planches d'images côte à côte, comme les personnages :
## on avance la fenêtre, et l'on retire le nœud à la dernière.
func _jouer_effet(planche: String, images: int, cote: int, ou: Vector2,
		angle_deg: float, cadence: float, pivot_x := 0.0) -> Sprite2D:
	var vue := Sprite2D.new()
	var region := AtlasTexture.new()
	region.atlas = load(DONNEES + planche)
	region.region = Rect2(0, 0, cote, cote)
	vue.texture = region
	vue.offset = Vector2(cote / 2.0 - pivot_x, 0)
	vue.rotation_degrees = angle_deg
	vue.position = ou
	add_child(vue)

	var minuteur := Timer.new()
	minuteur.wait_time = cadence
	vue.add_child(minuteur)

	# Le compteur vit dans un dictionnaire, non dans une variable.
	#
	# Les fonctions anonymes de GDScript capturent par valeur : incrémenter un
	# entier de l'extérieur ne modifie qu'une copie, et le compte ne monte
	# jamais. Les arcs ne mouraient donc pas — ils s'empilaient, et c'est cet
	# empilement qu'on prenait pour une auréole autour du personnage. Un
	# dictionnaire, lui, se capture par référence.
	var etat := { "image": 0 }
	minuteur.timeout.connect(func() -> void:
		etat["image"] += 1
		if etat["image"] >= images:
			vue.queue_free()
			return
		region.region = Rect2(int(etat["image"]) * cote, 0, cote, cote))
	minuteur.start()
	return vue


func _etincelle(ou: Vector2, teinte: Color, duree: float) -> void:
	# La gerbe d'impact : trois images qui s'ouvrent. La teinte demandée règle
	# l'ardeur, pour distinguer un coup porté d'un adversaire qui tombe.
	var vue := _jouer_effet("eclat.png", 3, ECLAT_COTE, ou, 0.0, duree / 3.0)
	vue.modulate = teinte


## Les sorts en vol : on les avance, on regarde ce qu'ils rencontrent.
func _avancer_les_traits(delta: float) -> void:
	for i in range(_traits.size() - 1, -1, -1):
		var trait_ = _traits[i]
		var porteur: Node2D = trait_["noeud"]
		if not is_instance_valid(porteur):
			_traits.remove_at(i)
			continue

		var pas: float = VITESSE_SORT * delta
		porteur.position += trait_["sens"] * pas
		trait_["reste"] -= pas

		var atteint := false
		for e in _ennemis:
			if not is_instance_valid(e["noeud"]):
				continue
			var qui: Combattant = e["noeud"]
			if not qui.vivant():
				continue
			if porteur.position.distance_to(qui.global_position + Vector2(0, -10)) < 12.0:
				# La carapace refuse le sort : `encaisser` rend faux, et le trait
				# poursuit sa course au lieu de s'éteindre. Le joueur voit que ça
				# ne prend pas.
				if qui.encaisser(_degats_sort(), "magie"):
					_etincelle(porteur.position, Color("#ffffff"), 0.21)
					_sons.jouer("sort-touche")
					atteint = true
					break
				elif qui.immunise_magie and not trait_.get("glisse", false):
					# La carapace refuse, et cela s'entend une fois — non à
					# chaque image de la traversée, qui crépiterait. Le son ne
					# ressemble à aucun autre : c'est une règle du texte qui
					# s'énonce, pas un coup manqué.
					trait_["glisse"] = true
					_sons.jouer("sort-glisse")

		if atteint or trait_["reste"] <= 0.0:
			porteur.queue_free()
			_traits.remove_at(i)


## Fait avancer ceux qui entrent ou qui s'en vont.
func _avancer_les_marcheurs(delta: float) -> void:
	for i in range(_marcheurs.size() - 1, -1, -1):
		var m: Dictionary = _marcheurs[i]
		var corps = m["corps"]
		if not is_instance_valid(corps):
			_marcheurs.remove_at(i)
			continue

		var reste: Vector2 = m["cible"] - corps.position
		if reste.length() <= 2.0:
			corps.position = m["cible"]
			if m["sortir"]:
				corps.queue_free()
			else:
				_poser(m["vue"], 0, _sens_de(reste))
			_marcheurs.remove_at(i)
			continue

		# Un peu moins vif que Wellan : il marche, il ne le course pas.
		corps.position += reste.normalized() * VITESSE * 0.75 * delta
		m["phase"] = fmod(m["phase"] + delta * CADENCE, 4.0)
		_poser(m["vue"], int(m["phase"]), _sens_de(reste))


## Le sens dominant d'un déplacement.
func _sens_de(v: Vector2) -> String:
	if absf(v.x) > absf(v.y):
		return "est" if v.x > 0.0 else "ouest"
	return "sud" if v.y > 0.0 else "nord"


## Pose une image de planche sur un sprite.
func _poser(vue, colonne: int, sens: String) -> void:
	if vue == null or not (vue.texture is AtlasTexture):
		return
	var region: AtlasTexture = vue.texture
	region.region = Rect2(colonne * SPRITE, RANGEE[sens] * SPRITE, SPRITE, SPRITE)


func _physics_process(delta: float) -> void:
	if _en_pause:
		_wellan.velocity = Vector2.ZERO
		return

	# Les bulles montent et descendent doucement : immobiles elles se prennent
	# pour un élément du décor, et l'œil cesse de les voir.
	_flottement += delta * 3.0
	var hauteur := -38.0 + sin(_flottement) * 2.0
	for id in _bulles:
		if is_instance_valid(_bulles[id]):
			_bulles[id].position.y = hauteur

	# Avant tout le reste : ceux qui entrent ou s'en vont avancent même pendant
	# un dialogue ou le carton d'ouverture. Une arrivée qui se fige parce qu'on
	# lit une réplique se verrait aussitôt.
	_avancer_les_marcheurs(delta)

	_energie = minf(_energie + REGAIN * delta, ENERGIE_MAX)
	_ui.jauges(_wellan.vie, _wellan.vie_max, _energie, ENERGIE_MAX)

	if _wellan.vie > 0 and _wellan.vie < _wellan.vie_max:
		_vie_dodue = minf(_vie_dodue + REGAIN_VIE * delta, float(_wellan.vie_max))
		if int(_vie_dodue) > _wellan.vie:
			_wellan.vie = int(_vie_dodue)
			_jauger(_wellan.vie, _wellan.vie_max)
	_choisir_l_interlocuteur()

	if _vaincu:
		_wellan.velocity = Vector2.ZERO
		return

	_avancer_les_traits(delta)

	# Les adversaires attendent la fin de l'échange : être mordu pendant qu'on
	# lit une réplique qu'on ne peut pas interrompre serait une punition sans
	# recours.
	if not _ouverte and not _ui.acheve_visible():
		_mener_les_ennemis(delta)
		_avancer_si_possible()

	if _ouverte:
		_wellan.velocity = Vector2.ZERO
		_dessiner(0)
		return

	var pas := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var court := Input.is_action_pressed("courir")
	# La vitesse vient des statistiques ; la course garde son rapport.
	var allure := _vitesse()
	_wellan.velocity = pas * (allure * (VITESSE_COURSE / VITESSE) if court else allure)
	_wellan.move_and_slide()

	if pas == Vector2.ZERO:
		_phase = 0.0
		_dessiner(0)
		return

	# La direction regardée suit l'axe dominant : en diagonale, on continue de
	# faire face au côté vers lequel on avance le plus franchement.
	if absf(pas.x) > absf(pas.y):
		_direction = "est" if pas.x > 0.0 else "ouest"
	else:
		_direction = "sud" if pas.y > 0.0 else "nord"

	# La cadence des jambes suit la vitesse. Sans cela, Wellan glisse en courant
	# — le pas reste celui de la marche pendant que le décor défile deux fois
	# plus vite, et c'est le genre de faute qu'on voit sans savoir la nommer.
	var cadence := CADENCE * (VITESSE_COURSE / VITESSE) if court else CADENCE
	cadence *= allure / VITESSE
	_phase = fmod(_phase + delta * cadence, 4.0)
	_dessiner(int(_phase))


func _dessiner(colonne: int) -> void:
	var region: AtlasTexture = _vue.texture
	region.region = Rect2(colonne * SPRITE, RANGEE[_direction] * SPRITE, SPRITE, SPRITE)

