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
const CADENCE := 7.0

## Rangée de la planche pour chaque direction regardée.
const RANGEE := { "sud": 0, "nord": 1, "ouest": 2, "est": 3 }

const DONNEES := "res://donnees/"
const Partie := preload("res://partie.gd")
## Le banc d'essai ne se charge que si on l'appelle : le jeu livré ne le voit
## jamais s'exécuter, et il ne pèse rien dans le fichier qu'il vérifie.
const Banc := preload("res://banc.gd")
const Interface := preload("res://interface.gd")
const Donnees := preload("res://donnees.gd")

## Le combat, en clair. Ces nombres sont à nous ; ce qui vient du texte, c'est
## que la carapace des hommes-insectes boit la magie.
## Vingt-quatre points au lieu de huit : à huit, deux coups de lance suffisaient
## et l'on rejouait la vague avant d'avoir compris ce qui l'avait tuée.
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

var _monde: Dictionary
var _salle: Dictionary
var _scene: Dictionary
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

var _marcheurs: Array = []   ## ceux qui entrent ou sortent, en chemin
var _bulles := {}            ## les bulles de parole, par identifiant de fiche
var _objets := {}            ## ce qu'on peut examiner, par clé
var _cloture_dite := false
## Ce qu'on a entendu, étape par étape, pour tout le chapitre. `_parles` ne vaut
## que pour l'étape en cours ; ceci survit et sert à rattraper.
var _entendus := {}
var _cle_courante := ""
var _flottement := 0.0
var _choix_pause := 0
var _en_pause := false
var _au_codex := false
var _choix_codex := 0
var _fiches_codex := []
var _recit_capture := false   ## une seule image de description suffit au contrôle
var _invite_capture := false
var _bulles_capture := false
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
	_salle = _lire(DONNEES + "salles/%s.json" % _scene.get("salle", ""))
	if _monde.is_empty() or _salle.is_empty() or _scene.is_empty():
		push_error("Données absentes. Lancer : npm run jeu:donnees")
		return

	_declarer_les_touches()
	_batir_le_sol()
	_batir_les_murs()
	_batir_wellan()
	_ui = Interface.new()
	add_child(_ui)
	_peupler()
	_tomber_la_nuit()
	_entrer_dans_l_etape()
	_annoncer_le_chapitre()

	# Le drapeau peut arriver des deux côtés de `++` selon la façon dont on
	# lance : on regarde les deux listes plutôt que d'imposer un ordre.
	if OS.get_cmdline_args().has("--capture") or OS.get_cmdline_user_args().has("--capture"):
		_banc = Banc.new(self)
		_banc._capturer()
	elif OS.get_cmdline_user_args().has("--effets"):
		_banc = Banc.new(self)
		_banc._capturer_les_effets()


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
			["suivant", KEY_ENTER]]:
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
	add_child(carte)

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
func _batir_les_murs() -> void:
	var sol := Rect2(Vector2.ZERO, Vector2(_taille()) * TUILE)
	var mur := 8.0

	var cadre := ColorRect.new()
	cadre.color = Color("#0b0a10")
	cadre.position = sol.position - Vector2(mur * 8, mur * 8)
	cadre.size = sol.size + Vector2(mur * 16, mur * 16)
	cadre.z_index = -10
	add_child(cadre)

	var corps := StaticBody2D.new()
	add_child(corps)
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
	_wellan.vie_max = VIE_WELLAN
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

	var taille := _taille()
	var camera := Camera2D.new()
	camera.zoom = Vector2(2, 2)
	camera.limit_left = -8
	camera.limit_top = -8
	camera.limit_right = taille.x * TUILE + 8
	camera.limit_bottom = taille.y * TUILE + 8
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	_wellan.add_child(camera)

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


func _peupler() -> void:
	for habitant in _salle.get("personnages", []):
		_faire_entrer(habitant, false)
	for objet in _salle.get("objets", []):
		_batir_objet(objet)


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
	var depart := arrivee
	if en_marchant:
		var seuil := _seuil(place)
		if habitant.has("depuis"):
			seuil = Vector2i(int(habitant["depuis"][0]), int(habitant["depuis"][1]))
		depart = Vector2(seuil) * TUILE

	var corps := StaticBody2D.new()
	corps.position = depart
	add_child(corps)

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

	for sortant in etape.get("disparaissent", []):
		_faire_sortir(str(sortant))
	for entrant in etape.get("apparaissent", []):
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
			_wellan.encaisser(int(e["degats"]), "fer")


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
		_ui.acheve("%s — achevé.\nEntrée pour « %s », ou restez encore."
			% [str(_scene.get("titre", "")), Partie.titre(suivant)])


## Wellan tombe.
##
## Un panneau qui s'affiche pendant que le personnage reste debout ne dit pas
## qu'il est mort, il dit que la partie s'arrête. Le sprite bascule donc au sol
## et une mare s'élargit sous lui — c'est ce qu'on voit qui doit porter la
## nouvelle, non le texte par-dessus.
func _perdre() -> void:
	_vaincu = true
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
		if not ici.has(id):
			return {}
		return { "cle": "%d:%s" % [_etape, id], "lignes": ici[id] }

	var trouvees := []
	for i in _toutes_les_etapes().size():
		var d: Dictionary = (_toutes_les_etapes()[i] as Dictionary).get("dialogues", {})
		if d.has(id):
			trouvees.append({ "cle": "%d:%s" % [i, id], "lignes": d[id] })
	for t in trouvees:
		if not _entendus.has(t["cle"]):
			return t
	return trouvees[-1] if not trouvees.is_empty() else {}


## A-t-on quelque chose à échanger avec lui ?
func _abordable(id: String) -> bool:
	if id.begins_with("objet:"):
		return _objets.has(id)
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
		_ui.invite(_proche != "")


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
	_objets[cle] = { "nom": str(objet.get("nom", "")), "texte": texte }

	var socle := Node2D.new()
	socle.position = ou
	add_child(socle)
	_zone_de_parole(socle, cle)
	_habitants[cle] = socle


## Les sortes de mobilier, dans l'ordre de la planche `objets.png`.
const MOBILIER := ["brasier", "banniere", "coffre", "trone", "stele", "autel", "tombe", "feu"]

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
	var n := MOBILIER.find(genre)
	var region := AtlasTexture.new()
	region.atlas = load(DONNEES + "objets.png")
	region.region = Rect2(maxi(n, 0) * SPRITE, 0, SPRITE, SPRITE)
	vue.texture = region
	# Calé par le bas, comme un personnage : un trône ou une bannière montent
	# plus haut qu'une tuile, et c'est leur pied qui touche le sol.
	vue.offset = Vector2(0, -SPRITE / 2.0 + 2)
	vue.position = ou
	add_child(vue)

	if genre == "brasier" and _scene.get("ambiance", {}).get("lumieres", false):
		var feu := PointLight2D.new()
		feu.texture = _halo(96)
		feu.color = Color("#f0d174")
		feu.energy = 1.5
		feu.position = ou
		add_child(feu)


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
			_interlocuteur = ""
			_avancer_si_possible()
			_rafraichir_les_bulles()
		elif _cloture_dite and not _ui.acheve_visible():
			# La clôture vient de se terminer : l'écran de fin peut paraître.
			_achever_le_chapitre()
		return
	var page: Dictionary = _pages[_page]
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


const CHOIX_PAUSE := ["Reprendre", "Codex", "Sauvegarder", "Écran-titre"]

func _dessiner_la_pause(mot := "") -> void:
	_ui.pause(_en_pause, _choix_pause, CHOIX_PAUSE, mot)


func _basculer_la_pause() -> void:
	_en_pause = not _en_pause
	_choix_pause = 0
	_ui.pause(_en_pause)
	if _en_pause:
		_wellan.velocity = Vector2.ZERO
		_dessiner_la_pause()


## Ce que fait l'entrée choisie.
##
## Reconnue par son nom et non par son rang : intercaler « Codex » en deuxième
## position aurait fait de « Sauvegarder » un retour à l'écran-titre, et rien
## dans le code ne l'aurait signalé.
func _choisir_dans_la_pause() -> void:
	match CHOIX_PAUSE[_choix_pause]:
		"Reprendre":
			_basculer_la_pause()
		"Codex":
			_ouvrir_le_codex()
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
	if _monde["personnages"].has(id):
		Partie.rencontrer(id)


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
	# Le Codex passe même avant la pause : Échap doit refermer le recueil et
	# rendre le menu, non quitter les deux d'un coup.
	if _au_codex:
		if evenement.is_action_pressed("pause") or evenement.is_action_pressed("ui_cancel"):
			_fermer_le_codex()
		elif evenement.is_action_pressed("ui_down") and not _fiches_codex.is_empty():
			_choix_codex = (_choix_codex + 1) % _fiches_codex.size()
			_ui.codex(true, _fiches_codex, _choix_codex, _monde["personnages"].size())
		elif evenement.is_action_pressed("ui_up") and not _fiches_codex.is_empty():
			_choix_codex = (_choix_codex + _fiches_codex.size() - 1) % _fiches_codex.size()
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
			_dessiner_la_pause()
		elif evenement.is_action_pressed("ui_up"):
			_choix_pause = (_choix_pause + CHOIX_PAUSE.size() - 1) % CHOIX_PAUSE.size()
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
	elif _proche.begins_with("objet:"):
		var chose: Dictionary = _objets.get(_proche, {})
		var lignes: Array = chose.get("texte", [])
		var nom := str(chose.get("nom", ""))
		if nom != "":
			lignes = [nom] + lignes
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
	for touche in get_world_2d().direct_space_state.intersect_shape(demande, 8):
		var qui = touche.get("collider")
		if qui is Combattant and qui != _wellan:
			qui.encaisser(DEGATS_EPEE, "fer")

	# L'arc part du personnage, non de la zone frappée : c'est le geste qu'on
	# montre, et il doit sortir de la main.
	_jouer_effet("taillade.png", 3, TAILLADE, _wellan.global_position + Vector2(0, -10),
		QUART.get(_direction, 0.0), REPOS_EPEE / 4.0, 8.0)


## Le feu de Theandras, déesse protectrice des Chevaliers.
func _lancer() -> void:
	if _energie < COUT_DU_SORT:
		return
	_energie -= COUT_DU_SORT

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
				if qui.encaisser(DEGATS_SORT, "magie"):
					_etincelle(porteur.position, Color("#ffffff"), 0.21)
					atteint = true
					break

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
	_wellan.velocity = pas * VITESSE
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

	_phase = fmod(_phase + delta * CADENCE, 4.0)
	_dessiner(int(_phase))


func _dessiner(colonne: int) -> void:
	var region: AtlasTexture = _vue.texture
	region.region = Rect2(colonne * SPRITE, RANGEE[_direction] * SPRITE, SPRITE, SPRITE)

