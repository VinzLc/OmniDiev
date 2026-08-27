extends RefCounted

const Partie := preload("res://partie.gd")
##
## Le banc d'essai : il joue la partie à la place d'un joueur et enregistre ce
## qu'il voit.
##
## Il vivait dans `main.gd`, où il occupait dix-sept pour cent du fichier. Un
## harnais de vérification n'a pas à grossir le code qu'il vérifie, et le
## séparer rend visible ce qu'il touche : tout ce qui appartient au jeu passe
## désormais par `jeu.`, explicitement.
##
## Il passe par `Input.parse_input_event` : le chemin traversé est celui d'un
## joueur, touches comprises. Une vérification qui contourne le chemin normal
## ne prouve rien de ce chemin.

var jeu: Node2D


func _init(scene: Node2D) -> void:
	jeu = scene


## Joue le chapitre courant jusqu'à sa clôture, puis passe au suivant.
##
## L'épreuve de la campagne n'est pas qu'un chapitre se joue — c'est qu'il en
## appelle un autre, et que la partie se retrouve où on l'avait laissée.
func _capturer() -> void:
	# Le carton d'abord : c'est la première chose que voit un joueur, donc la
	# première qu'il faut regarder.
	await _attendre(6)
	jeu.get_viewport().get_texture().get_image().save_png("res://capture-carton.png")
	jeu._ui.fermer_carton()

	# La narration d'ouverture, que le carton enchaîne pour un joueur.
	jeu._reciter(jeu._scene.get("ouverture", []))
	if jeu._ouverte:
		await _attendre(4)
		jeu.get_viewport().get_texture().get_image().save_png("res://capture-ouverture.png")
		print("OUVERTURE %d page(s)" % jeu._pages.size())
		while jeu._ouverte:
			_touche("ui_accept")
			await _attendre(2)

	# Une vue d'ensemble de la salle, mobilier compris : on ne vérifie pas un
	# décor sur une capture centrée à deux tuiles du personnage.
	var taille: Vector2i = jeu._taille()
	jeu._wellan.global_position = Vector2(taille) * jeu.TUILE / 2.0
	await _attendre(8)
	jeu.get_viewport().get_texture().get_image().save_png("res://capture-salle.png")

	# Un objet du décor : il faut pouvoir le regarder de près.
	var chose := ""
	for cle in jeu._objets:
		chose = str(cle)
		break
	if chose != "":
		jeu._wellan.global_position = jeu._habitants[chose].position + Vector2(0, jeu.TUILE)
		var patience := 0
		while jeu._proche != chose and patience < 90:
			await jeu.get_tree().process_frame
			patience += 1
		if jeu._proche == chose:
			_touche("ui_accept")
			await _attendre(4)
			jeu.get_viewport().get_texture().get_image().save_png("res://capture-objet.png")
			print("OBJET %s — %s" % [chose, jeu._objets[chose]["nom"]])
			while jeu._ouverte:
				_touche("ui_accept")
				await _attendre(2)
		else:
			print("OBJET hors de portée : %s" % chose)

	print("CHAPITRE %s — %s" % [jeu._chapitre, jeu._scene.get("titre", "")])
	await _garder("00-%s" % jeu._chapitre, 12)

	var garde := 0
	while not jeu._ui.acheve_visible() and garde < 40:
		garde += 1
		var etape: Dictionary = jeu._etape_courante()
		var attend: Dictionary = etape.get("attend", {})

		if attend.has("parler"):
			await _parler_a(str(attend["parler"]), "%02d-%s" % [garde, attend["parler"]])
		elif attend.has("parler_tous"):
			for id in attend["parler_tous"]:
				await _parler_a(str(id), "%02d-%s" % [garde, id])
		elif attend.has("vague_defaite"):
			# On abat la vague par le modèle : la mêlée a été éprouvée ailleurs,
			# ici c'est l'enchaînement des chapitres qu'on vérifie.
			for e in jeu._ennemis:
				if not is_instance_valid(e["noeud"]):
					continue
				var qui: Combattant = e["noeud"]
				while is_instance_valid(qui) and qui.vivant():
					qui.encaisser(99, "fer")
					await _attendre(30)
			await _attendre(20)
		else:
			break
		print("  → %s" % (jeu._ui.objectif_affiche() if jeu._ui.objectif_affiche() != "" else "(clôture)"))

	if jeu._ui.acheve_visible():
		var mot: String = jeu._ui.mot_acheve()
		print("ACHEVE : %s" % mot.replace("\n", " "))
	else:
		print("PAS ACHEVE après %d tours, étape %d" % [garde, jeu._etape])

	# Après la clôture, ce qui reste à entendre.
	jeu._rafraichir_les_bulles()
	await _attendre(4)
	var reste := PackedStringArray()
	for id in jeu._habitants:
		if not str(id).begins_with("objet:") and jeu._a_dire(str(id)):
			reste.append(str(id))
	print("APRES CLOTURE : %d personne(s) ont encore quelque chose à dire — %s" % [reste.size(), reste])
	jeu.get_viewport().get_texture().get_image().save_png("res://capture-apres.png")

	# Les réglages qu'on vient de changer, relevés plutôt que supposés.
	var lettres := PackedStringArray()
	for a in ["ui_up", "ui_left", "ui_down", "ui_right"]:
		for e in InputMap.action_get_events(a):
			if e is InputEventKey and e.physical_keycode in [KEY_W, KEY_A, KEY_S, KEY_D]:
				lettres.append(OS.get_keycode_string(e.physical_keycode))
	print("TOUCHES lettres=%s" % [lettres])
	print("VIE %d points, regain %.2f/s" % [jeu._wellan.vie_max, jeu.REGAIN_VIE])
	print("SORT %d dégâts, %d px/s, portée %d" % [jeu.DEGATS_SORT, int(jeu.VITESSE_SORT), int(jeu.PORTEE_SORT)])

	# La vie doit remonter d'elle-même — hors pause, sans quoi la boucle de
	# physique sort avant d'y arriver et l'on conclut que le regain ne marche
	# pas. L'épreuve de la pause précède celle-ci.
	jeu._en_pause = false
	jeu._ui.pause(false)
	jeu._wellan.vie = 4
	jeu._vie_dodue = 4.0
	# Un point demande près de deux secondes : attendre moins ne prouve rien.
	await _attendre(400)
	print("REGAIN 4 → %d points (%.1f en interne) sur %d" % [
		jeu._wellan.vie, jeu._vie_dodue, jeu._wellan.vie_max])

	# Et un personnage sans réplique écrite doit être muet.
	var muet := ""
	for id in jeu._habitants:
		if not str(id).begins_with("objet:") and not jeu._abordable(str(id)):
			muet = str(id)
			break
	print("MUET %s : abordable=%s" % [muet if muet != "" else "aucun", jeu._abordable(muet)])

	await _eprouver_les_orientations()

	# La pause : on doit pouvoir s'arrêter, et voir où l'on s'arrête.
	#
	# On écarte d'abord l'écran de fin de chapitre : tant qu'il est là, la pause
	# est ignorée — à raison — et l'appui suivant rechargerait la scène, ce qui
	# laisserait la capture sans viewport.
	jeu._ui.masquer_acheve()
	_touche("pause")
	await _attendre(6)
	jeu.get_viewport().get_texture().get_image().save_png("res://capture-pause.png")
	print("PAUSE ouverte=%s choix=%s" % [jeu._en_pause, jeu.CHOIX_PAUSE[jeu._choix_pause]])
	_touche("ui_down")
	await _attendre(3)
	_touche("ui_accept")
	await _attendre(6)
	jeu.get_viewport().get_texture().get_image().save_png("res://capture-pause-note.png")
	print("PAUSE après sauvegarde : %s" % Partie.courante())

	# « Sauvegarder » note le chapitre en cours — ce qui, ici, écrase l'avance
	# que la fin du chapitre venait d'inscrire. Le banc remet donc la partie où
	# le chapitre l'avait laissée : vérifier ne doit rien changer.
	var suivant: String = jeu._chapitre_suivant()
	if suivant != "":
		jeu._noter(suivant)
		print("PAUSE avance rendue : %s" % suivant)

	jeu.get_tree().quit()


## Les quatre orientations, sur un même personnage.
##
## Le parcours de campagne aborde toujours par le sud : il prouve que le
## personnage se tourne, jamais qu'il se tourne du bon côté. On éprouve donc la
## géométrie séparément, en déplaçant Wellan autour de lui.
func _eprouver_les_orientations() -> void:
	var cible := ""
	for id in jeu._habitants:
		cible = str(id)
		break
	if cible == "":
		print("ORIENTATION : plus personne dans la salle")
		return

	var corps: Node2D = jeu._habitants[cible]
	for essai in [
		{ "ou": Vector2(0, jeu.TUILE), "attendu": "sud" },
		{ "ou": Vector2(0, -jeu.TUILE), "attendu": "nord" },
		{ "ou": Vector2(jeu.TUILE, 0), "attendu": "est" },
		{ "ou": Vector2(-jeu.TUILE, 0), "attendu": "ouest" },
	]:
		jeu._wellan.global_position = corps.global_position + essai["ou"]
		jeu._tourner_vers_moi(cible)
		var rang := -1
		for enfant in corps.get_children():
			if enfant is Sprite2D and enfant.texture is AtlasTexture:
				rang = int((enfant.texture as AtlasTexture).region.position.y / jeu.SPRITE)
		var obtenu := "?"
		for sens in jeu.RANGEE:
			if jeu.RANGEE[sens] == rang:
				obtenu = sens
		print("ORIENTATION %s %s attendu, %s obtenu" % [
			"OK" if obtenu == essai["attendu"] else "FAUX", essai["attendu"], obtenu])


## Regarde les effets, image par image.
##
## On les prend pendant qu'ils jouent, non après : une animation captée à sa
## fin ne montre que le vide qu'elle laisse. C'est la même faute que la boîte de
## dialogue photographiée une fois fermée.
func _capturer_les_effets() -> void:
	jeu._ui.fermer_carton()

	await _attendre(20)
	if jeu._vague_debout() == 0 and not jeu._ennemis.is_empty():
		pass

	# La taillade, dans les quatre directions.
	for sens in ["sud", "est", "nord", "ouest"]:
		# Une prise par direction, bien séparée : trop rapprochées, l'arc
		# précédent traîne encore et l'on croit voir un anneau.
		await _attendre(40)
		jeu._direction = sens
		jeu._prochain_coup = 0.0
		jeu._frapper()
		await _attendre(5)
		var lames := 0
		for enfant in jeu.get_children():
			if enfant is Sprite2D and enfant.texture is AtlasTexture:
				var at: AtlasTexture = enfant.texture
				if str(at.atlas.resource_path).ends_with("taillade.png"):
					lames += 1
		print("  %s : %d lame(s) à l'écran" % [sens, lames])
		jeu.get_viewport().get_texture().get_image().save_png("res://capture-taillade-%s.png" % sens)
	print("jeu.TAILLADE dans quatre sens")

	# La boule de feu en vol, puis son éclat.
	jeu._direction = "est"
	jeu._energie = jeu.ENERGIE_MAX
	jeu._lancer()
	for n in 3:
		await _attendre(9)
		jeu.get_viewport().get_texture().get_image().save_png("res://capture-feu-%d.png" % n)
	print("FEU %d trait(s) en vol" % jeu._traits.size())

	jeu._etincelle(jeu._wellan.global_position + Vector2(28, -10), Color("#ffffff"), 0.3)
	await _attendre(4)
	jeu.get_viewport().get_texture().get_image().save_png("res://capture-eclat.png")
	print("ECLAT")

	# La mort, puis le relèvement. C'est ce qu'on voit qui doit dire qu'il est
	# mort, donc c'est ce qu'il faut regarder.
	jeu._wellan.vie = 0
	jeu._perdre()
	await _attendre(40)
	jeu.get_viewport().get_texture().get_image().save_png("res://capture-mort.png")
	print("MORT sprite tourné de %.0f°, mare %s" % [
		jeu._vue.rotation_degrees, "visible" if jeu._mare != null and jeu._mare.visible else "absente"])

	_touche("ui_accept")
	await _attendre(8)
	jeu.get_viewport().get_texture().get_image().save_png("res://capture-releve.png")
	print("RELEVE sprite à %.0f°, mare %s, vie %d" % [
		jeu._vue.rotation_degrees, "visible" if jeu._mare != null and jeu._mare.visible else "effacée", jeu._wellan.vie])

	jeu.get_tree().quit()


func _touche(action: String) -> void:
	var t := InputEventAction.new()
	t.action = action
	t.pressed = true
	Input.parse_input_event(t)


func _attendre(images: int) -> void:
	for i in images:
		await jeu.get_tree().process_frame


## Aborde un personnage et l'écoute jusqu'au bout.
func _parler_a(id: String, nom_image: String) -> void:
	if not jeu._habitants.has(id):
		print("ABSENT %s" % id)
		return
	# On laisse d'abord arriver ceux qui marchent : les aborder en chemin
	# reviendrait à courir après quelqu'un qui traverse la salle.
	var attente := 0
	var marchait := false
	while attente < 300 and jeu._marcheurs.any(func(m): return m["corps"] == jeu._habitants.get(id)):
		if not marchait:
			marchait = true
			print("MARCHE %s entre depuis %s" % [id, jeu._habitants[id].position / float(jeu.TUILE)])
		# Une image en pleine traversée : c'est le mouvement qu'il faut voir,
		# et il a disparu quand la conversation s'ouvre.
		if attente == 24:
			jeu.get_viewport().get_texture().get_image().save_png("res://capture-marche-%s.png" % id)
		await jeu.get_tree().process_frame
		attente += 1
	if marchait:
		print("ARRIVE %s en %d images, à %s" % [id, attente, jeu._habitants[id].position / float(jeu.TUILE)])

	jeu._wellan.global_position = jeu._habitants[id].position + Vector2(0, jeu.TUILE)
	# On attend que la zone réagisse au lieu de compter les images : au
	# démarrage, la compilation des shaders affame la physique et un nombre fixe
	# d'images ne garantit rien.
	var patience := 0
	while jeu._proche != id and patience < 120:
		await jeu.get_tree().process_frame
		patience += 1
	if jeu._proche != id:
		print("HORS DE PORTEE %s (proche=%s)" % [id, jeu._proche])
		return

	# Une image quand plusieurs bulles sont à l'écran : c'est là qu'on voit à
	# quoi elles servent — la quête des six Chevaliers.
	if jeu._bulles.size() >= 3 and not jeu._bulles_capture:
		jeu._bulles_capture = true
		await _attendre(3)
		jeu.get_viewport().get_texture().get_image().save_png("res://capture-bulles.png")
		print("BULLES %d à l'écran" % jeu._bulles.size())

	# Une image avant d'ouvrir : c'est le seul moment où l'invite se voit, et
	# elle est là pour être vue.
	if not jeu._invite_capture:
		jeu._invite_capture = true
		# Deux images d'attente : l'invite s'allume dans la passe de physique, et
		# le tampon dessiné a un tour de retard. Capturer aussitôt rendait un
		# écran où elle n'était pas encore peinte, et l'on aurait conclu qu'elle
		# ne s'affichait pas.
		await _attendre(3)
		jeu.get_viewport().get_texture().get_image().save_png("res://capture-invite.png")

	var pages := 0
	while pages < 12:
		_touche("ui_accept")
		await _attendre(2)
		pages += 1
		if pages == 2 and jeu._ouverte:
			jeu.get_viewport().get_texture().get_image().save_png("res://capture-%s.png" % nom_image)
		# Et une image dès qu'une description paraît : c'est l'autre affichage,
		# et rien ne prouverait autrement qu'il s'ouvre.
		# Une image quand Wellan parle : son portrait est le plus vu du jeu.
		if jeu._ouverte and not jeu._wellan_capture and jeu._page < jeu._pages.size() \
			and str((jeu._pages[jeu._page] as Dictionary).get("qui", "")) == "wellan":
			jeu._wellan_capture = true
			jeu.get_viewport().get_texture().get_image().save_png("res://capture-wellan-parle.png")
		if jeu._ui.recit_visible() and not jeu._recit_capture:
			jeu._recit_capture = true
			jeu.get_viewport().get_texture().get_image().save_png("res://capture-description.png")
		if not jeu._ouverte and pages > 1:
			break

	# Le personnage s'est-il tourné ? La rangée de sa planche le dit.
	var tourne := "?"
	if jeu._habitants.has(id):
		for enfant in jeu._habitants[id].get_children():
			if enfant is Sprite2D and enfant.texture is AtlasTexture:
				var rang := int((enfant.texture as AtlasTexture).region.position.y / jeu.SPRITE)
				for sens in jeu.RANGEE:
					if jeu.RANGEE[sens] == rang:
						tourne = sens
	print("PARLE %s en %d pages, regarde vers %s" % [id, pages, tourne])


func _garder(nom: String, images: int) -> void:
	await _attendre(images)
	jeu.get_viewport().get_texture().get_image().save_png("res://capture-%s.png" % nom)
