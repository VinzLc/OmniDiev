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

## Le mode rapide ne saisit aucune image.
##
## Une capture demande un viewport dessiné, donc une fenêtre. S'en passer laisse
## le contrôle tourner sans écran — et c'est ce qui le rend utilisable à chaque
## chapitre écrit plutôt qu'une fois par semaine.
var rapide := false


func _init(scene: Node2D) -> void:
	jeu = scene


## Joue le chapitre courant jusqu'à sa clôture, puis passe au suivant.
##
## L'épreuve de la campagne n'est pas qu'un chapitre se joue — c'est qu'il en
## appelle un autre, et que la partie se retrouve où on l'avait laissée.
func _capturer() -> void:
	# L'écran des commandes avant le carton, puisqu'il le couvre. C'est la toute
	# première chose que voit qui n'a jamais lancé le jeu — et c'est une image,
	# donc elle se regarde : rien ne mesure qu'une ligne déborde de son cadre ou
	# qu'une touche y manque.
	await _eprouver_les_commandes()

	# Le carton ensuite : la première chose que voit un joueur qui revient.
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

	# Le Codex encore vide, avant d'avoir parlé à qui que ce soit : c'est le seul
	# moment où l'on peut voir ce qu'il dit à un joueur qui ne connaît personne.
	# Après le carton, qui se dessine par-dessus tout et le masquerait.
	jeu._ouvrir_le_codex()
	await _attendre(4)
	jeu.get_viewport().get_texture().get_image().save_png("res://capture-codex-vide.png")
	var noms := PackedStringArray()
	for f in jeu._fiches_codex:
		noms.append(str((f as Dictionary).get("nom", "?")))
	print("CODEX au départ : %d fiche(s) — %s" % [jeu._fiches_codex.size(), noms])
	jeu._fermer_le_codex()
	jeu._ui.pause(false)

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

	# Le Château entier, porte après porte, avant que le chapitre commence : on
	# doit pouvoir en faire le tour et revenir là où l'histoire se joue.
	await _visiter_les_salles()

	print("SONS %d déclaré(s), %d chargé(s)%s" % [
		(jeu._monde.get("sons", []) as Array).size(), jeu._sons.charges(),
		"" if jeu._sons.manquants.is_empty() else " — MANQUANTS %s" % [jeu._sons.manquants]])

	await _eprouver_la_musique()
	await _eprouver_la_course()

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

	await _eprouver_le_registre()
	await _eprouver_les_habitants()

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

	# Le Codex, puisqu'on vient de parler à quelqu'un : il doit avoir retenu.
	await _descendre_jusqu_a("Codex")
	_touche("ui_accept")
	await _attendre(6)
	jeu.get_viewport().get_texture().get_image().save_png("res://capture-codex.png")
	print("CODEX ouvert=%s fiches=%d" % [jeu._ui.codex_visible(), jeu._fiches_codex.size()])
	if jeu._fiches_codex.size() > 1:
		_touche("ui_down")
		await _attendre(4)
		print("CODEX second choix : %s" % jeu._fiches_codex[jeu._choix_codex]["nom"])
	_touche("pause")
	await _attendre(4)
	print("CODEX refermé, pause rendue : %s" % (not jeu._ui.codex_visible() and jeu._en_pause))

	await _eprouver_la_carte()
	await _eprouver_les_chapitres()
	await _eprouver_le_sac()
	await _eprouver_les_commandes_du_menu()

	await _descendre_jusqu_a("Sauvegarder")
	_touche("ui_accept")
	await _attendre(6)
	jeu.get_viewport().get_texture().get_image().save_png("res://capture-pause-note.png")
	print("SONS joués pendant le chapitre : %s" % [jeu._sons.joues])

	print("PAUSE après sauvegarde : %s" % Partie.courante())

	# « Sauvegarder » note le chapitre en cours — ce qui, ici, écrase l'avance
	# que la fin du chapitre venait d'inscrire. Le banc remet donc la partie où
	# le chapitre l'avait laissée : vérifier ne doit rien changer.
	var suivant: String = jeu._chapitre_suivant()
	if suivant != "":
		jeu._noter(suivant)
		print("PAUSE avance rendue : %s" % suivant)

	jeu.get_tree().quit()


## L'effectif survit à la sortie.
##
## Une salle rebâtie d'après son fichier montrerait ce qu'il y avait au lever du
## rideau : Armène de retour alors qu'elle est repartie, la Reine absente alors
## qu'elle vient d'entrer. Rien n'échouerait, aucune erreur ne serait levée — le
## chapitre mentirait, et c'est la seule chose qu'on ne rattrape pas.
func _eprouver_le_registre() -> void:
	var ici: String = jeu._salle_id
	var avant := _qui_est_la()

	var sortie := ""
	for cle in jeu._passages:
		sortie = str(cle)
		break
	if sortie == "":
		print("REGISTRE : aucune porte dans %s, rien à éprouver" % ici)
		return
	if not await _franchir_la_porte(sortie):
		return

	var retour := ""
	for c in jeu._passages:
		if str(jeu._passages[c]["vers"]) == ici:
			retour = str(c)
	if retour == "" or not await _franchir_la_porte(retour):
		print("REGISTRE : pas de retour vers %s" % ici)
		return

	var apres := _qui_est_la()
	print("REGISTRE avant la sortie : %s" % [avant])
	print("REGISTRE après le retour  : %s" % [apres])
	print("REGISTRE %s" % ("intact" if avant == apres else "DIVERGENT"))


func _qui_est_la() -> Array:
	var noms := PackedStringArray()
	for id in jeu._habitants:
		if not str(id).begins_with("objet:"):
			noms.append(str(id))
	noms.sort()
	return Array(noms)


## Ouvre tout ce qui contient quelque chose, dans la salle où l'on est.
##
## Par la touche, comme un joueur : on se place devant le meuble, on attend que
## le jeu le propose, on presse. Appeler `Partie.prendre` directement prouverait
## que la sauvegarde retient, jamais que le coffre rend.
func _vider_les_coffres(ou: String) -> void:
	var pleins := []
	for cle in jeu._objets:
		if not (jeu._objets[cle] as Dictionary).get("contient", {}).is_empty():
			pleins.append(str(cle))
	if pleins.is_empty():
		return

	var avant: int = Partie.sac().size()
	for cle in pleins:
		if not jeu._habitants.has(cle):
			continue
		jeu._wellan.global_position = jeu._habitants[cle].position + Vector2(0, jeu.TUILE)
		var patience := 0
		while jeu._proche != cle and patience < 120:
			await jeu.get_tree().process_frame
			patience += 1
		if jeu._proche != cle:
			print("COFFRE hors de portée : %s" % cle)
			continue
		_touche("ui_accept")
		await _attendre(4)
		while jeu._ouverte:
			_touche("ui_accept")
			await _attendre(2)

		# Le coffre s'ouvre après la description, et rien n'en sort tout seul :
		# on prend pièce par pièce, comme un joueur.
		if jeu._ui.butin_visible() and not rapide and not jeu._butin_capture:
			jeu._butin_capture = true
			await _attendre(3)
			jeu.get_viewport().get_texture().get_image().save_png("res://capture-butin.png")
			print("BUTIN « %s » : %d pièce(s)" % [
				str((jeu._objets[cle] as Dictionary)["nom"]), jeu._contenu_butin.size()])
		var garde := 0
		while jeu._ui.butin_visible() and garde < 12:
			_touche("ui_accept")
			await _attendre(4)
			garde += 1
	print("COFFRES %s : %d ouvert(s), sac %d → %d" % [ou, pleins.size(), avant, Partie.sac().size()])


## Les habitants de la salle, et leur date d'arrivée.
##
## Ce qu'on mesure : qu'un habitant daté ne paraisse pas avant son chapitre.
## Nogait est l'Écuyer de Jasson et les Écuyers ne sont attribués qu'au chapitre
## I,15 — le trouver dans la galerie au premier chapitre serait une faute de
## suite que rien d'autre ne signalerait.
##
## Et qu'il parle, une fois là : ses répliques vivent dans la salle et non dans
## une étape, donc elles ne passent par aucun des contrôles de scène.
func _eprouver_les_habitants() -> void:
	# La main au jeu d'abord. Cette épreuve tournait au milieu des écrans de
	# pause : la passe de physique sort avant de calculer un interlocuteur, donc
	# `_proche` restait vide et l'on concluait que l'habitant était hors de
	# portée alors qu'on se tenait sur lui.
	jeu._en_pause = false
	jeu._ui.pause(false)
	jeu._ouverte = false
	await _attendre(4)

	# Toutes les salles, non la seule où l'on se trouve : un habitant daté qui
	# paraîtrait trop tôt le ferait dans sa salle à lui, où l'on n'est pas.
	var ouvert := PackedStringArray()
	var ferme := PackedStringArray()
	var d := DirAccess.open("res://donnees/salles")
	if d:
		for f in d.get_files():
			if not f.ends_with(".json"):
				continue
			var ou := f.substr(0, f.length() - 5)
			for h in jeu._effectif_de(ou):
				var fiche := str((h as Dictionary).get("fiche", ""))
				var des := str((h as Dictionary).get("des", ""))
				if des == "":
					continue
				if Partie.rang(jeu._chapitre) >= Partie.rang(des):
					ouvert.append("%s (%s, dès %s)" % [fiche, ou, des])
				else:
					ferme.append("%s (%s, dès %s)" % [fiche, ou, des])

	print("HABITANTS au chapitre %s — arrivés : %s" % [
		jeu._chapitre, "aucun" if ouvert.is_empty() else ", ".join(ouvert)])
	print("HABITANTS pas encore : %s" % ["aucun" if ferme.is_empty() else ", ".join(ferme)])

	var muets := PackedStringArray()
	for h in jeu._effectif_de(jeu._salle_id):
		var fiche := str((h as Dictionary).get("fiche", ""))
		if str((h as Dictionary).get("des", "")) != "" and jeu._habitants.has(fiche) \
			and jeu._paroles_de_la_salle(fiche).is_empty():
			muets.append(fiche)
	if not muets.is_empty():
		print("HABITANTS SANS RÉPLIQUE : %s" % [muets])

	# Et l'on va vraiment lui parler, par le chemin d'un joueur.
	for h in jeu._effectif_de(jeu._salle_id):
		var fiche := str((h as Dictionary).get("fiche", ""))
		if str((h as Dictionary).get("des", "")) == "" or not jeu._habitants.has(fiche):
			continue
		await _parler_a(fiche, "habitant-%s" % fiche)
		print("HABITANT %s abordé — clé « %s », bulle encore due : %s" % [
			fiche, str(jeu._paroles_de_la_salle(fiche).get("cle", "?")), jeu._a_dire(fiche)])
		await _eprouver_le_don(fiche)
		break


## Le présent qu'un habitant tend, et ce qu'il change.
##
## Ce qu'on mesure, et qu'aucune autre épreuve ne mesure : que la fenêtre
## s'ouvre **après** la dernière réplique et non pendant, qu'elle nomme le
## donneur, que prendre la pièce la range au sac — et **que le barème bouge**.
## Un présent qu'on accepte sans que rien ne change serait un dialogue avec une
## animation, non une récompense.
func _eprouver_le_don(fiche: String) -> void:
	if not jeu._offres.has(fiche):
		return
	var offert: Dictionary = jeu._offres[fiche]
	var quoi := str(offert.get("id", "?"))
	if jeu._au_butin != "personne:%s" % fiche:
		# Déjà au sac, la fenêtre n'a rien à montrer et se tait : c'est le
		# comportement voulu, non une panne. Sans cette distinction le banc
		# criait à la panne dès le second passage sur le même carnet d'essai —
		# et l'on aurait cherché le défaut dans le moteur.
		if Partie.sac().has(quoi):
			print("DON %s : « %s » déjà pris lors d'un tour précédent, rien à rouvrir" % [fiche, quoi])
		else:
			print("DON %s : la fenêtre ne s'est pas ouverte (au_butin=« %s »)" % [fiche, jeu._au_butin])
		return
	if not rapide:
		await _attendre(3)
		jeu.get_viewport().get_texture().get_image().save_png("res://capture-don-%s.png" % fiche)

	var ou := str(offert.get("emplacement", ""))
	var avant := int(jeu._stats.get(_menee(offert), 0))
	_touche("ui_accept")
	await _attendre(6)
	var au_sac: bool = Partie.sac().has(quoi)
	# Le sac ne suffit pas : il faut la porter pour que le barème bouge, et
	# c'est la porter qui prouve que l'emplacement déclaré existe vraiment.
	if au_sac and ou != "":
		Partie.equiper(ou, quoi)
		jeu._recalculer_les_stats()
	var apres := int(jeu._stats.get(_menee(offert), 0))
	print("DON %s → « %s » (%s) au sac : %s · %s %d → %d" % [
		fiche, quoi, ou, au_sac, _menee(offert), avant, apres])


## La statistique qu'une pièce mène, celle dont le bonus est le plus fort.
func _menee(prise: Dictionary) -> String:
	var bonus: Dictionary = prise.get("bonus", {})
	var quelle := "defense"
	var haut := -99
	for cle in bonus:
		if int(bonus[cle]) > haut:
			haut = int(bonus[cle])
			quelle = str(cle)
	return quelle


## La carte, et le voyage.
##
## Ce qu'on mesure : que l'écran s'ouvre, qu'on puisse viser une autre escale,
## et surtout **que s'y rendre change réellement de salle et le retienne**. Le
## monde est ouvert, donc l'endroit fait partie de la partie : une position qui
## ne se garde pas ramènerait le joueur au Château à chaque relance.
func _eprouver_la_carte() -> void:
	var avant: String = jeu._salle_id

	await _descendre_jusqu_a("Carte")
	_touche("ui_accept")
	await _attendre(8)
	jeu.get_viewport().get_texture().get_image().save_png("res://capture-carte.png")
	print("CARTE %d escale(s), on est à « %s »" % [
		jeu._escales.size(), str((jeu._escales[jeu._choix_carte] as Dictionary)["nom"])])

	# Viser ailleurs : on essaie les quatre sens jusqu'à ce que le choix bouge.
	var vise: int = jeu._choix_carte
	for sens in ["ui_right", "ui_down", "ui_left", "ui_up"]:
		_touche(sens)
		await _attendre(4)
		if jeu._choix_carte != vise:
			break
	if jeu._choix_carte == vise:
		print("CARTE : aucune escale atteignable depuis celle-ci")
		_touche("pause")
		await _attendre(4)
		return
	var but: Dictionary = jeu._escales[jeu._choix_carte]
	print("CARTE visé « %s »" % str(but["nom"]))
	jeu.get_viewport().get_texture().get_image().save_png("res://capture-carte-vise.png")

	_touche("ui_accept")
	await _attendre(10)
	print("VOYAGE %s → %s : %s" % [avant, jeu._salle_id,
		"arrivé" if jeu._salle_id != avant else "N A PAS BOUGÉ"])
	print("VOYAGE retenu dans la partie : %s" % [Partie.retenu("salle", "—")])
	print("VOYAGE le chapitre suit : ici=%s, objectif « %s »" % [
		jeu._chapitre_ici(), jeu._ui.objectif_affiche()])

	# Et l'on rentre, pour que la suite du banc retrouve sa salle.
	if jeu._salle_id != avant:
		_touche("pause")
		await _attendre(4)
		await _descendre_jusqu_a("Carte")
		_touche("ui_accept")
		await _attendre(6)
		for i in jeu._escales.size():
			if str((jeu._escales[i] as Dictionary)["salle"]) == avant \
				or str((jeu._escales[i] as Dictionary)["lieu"]) == str(jeu._lieu_du_chapitre()):
				jeu._choix_carte = i
		jeu._ui.carte(true, { "escales": jeu._escales, "choix": jeu._choix_carte })
		_touche("ui_accept")
		await _attendre(10)
		print("VOYAGE retour : %s" % jeu._salle_id)
	_touche("pause")
	await _attendre(4)


## Les chapitres, et surtout ce qu'ils ne doivent pas casser.
##
## L'écran se regarde sur la capture. Ce qui se mesure, c'est l'invariant :
## rejouer un chapitre ancien ne doit pas faire reculer l'avance. La sauvegarde
## ne portait que « où j'en suis » ; le jour où l'on rejoue le premier chapitre,
## « où j'en suis » vaudrait soudain « chapitre un », et vingt-cinq chapitres
## d'avance disparaîtraient sans un mot.
func _eprouver_les_chapitres() -> void:
	# Une scène imposée ne note rien : le carnet d'essai n'a donc aucune avance.
	# On lui en donne une le temps de l'épreuve — c'est son carnet, pas celui du
	# joueur.
	Partie.noter("i-03")

	await _descendre_jusqu_a("Chapitres")
	_touche("ui_accept")
	await _attendre(6)
	jeu.get_viewport().get_texture().get_image().save_png("res://capture-chapitres.png")

	var ouverts := 0
	var ferme := -1
	for i in jeu._liste_chapitres.size():
		if bool((jeu._liste_chapitres[i] as Dictionary)["joue"]):
			ouverts += 1
		elif ferme < 0:
			ferme = i
	print("CHAPITRES %d dans la campagne, %d ouverts jusqu'à « %s »" % [
		jeu._liste_chapitres.size(), ouverts, Partie.atteint()])

	# L'avance, mise à l'épreuve d'une note en arrière.
	var avance := Partie.atteint()
	Partie.noter("i-01")
	print("AVANCE %s, on note i-01 → %s — %s" % [
		avance, Partie.atteint(), "tenue" if Partie.atteint() == avance else "PERDUE"])
	Partie.noter(avance)

	# Et le verrou : un chapitre qu'on n'a pas atteint ne se rejoue pas. S'il
	# cédait, la scène se rechargerait et le banc mourrait ici — ce qui est
	# encore la meilleure façon de l'apprendre.
	if ferme >= 0:
		jeu._choix_chapitre = ferme
		_touche("ui_accept")
		await _attendre(8)
		print("CHAPITRES verrou : « %s » refusé, écran tenu : %s" % [
			str((jeu._liste_chapitres[ferme] as Dictionary)["titre"]),
			jeu._ui.chapitres_visible()])
	else:
		print("CHAPITRES : tous ouverts, verrou non éprouvé")

	# Le mécanisme du rejeu lui-même, sans recharger la scène : on pose la
	# demande et l'on regarde ce que le jeu ouvrirait. Recharger pour de bon
	# ferait repartir le banc du début.
	Partie.rejoue = "i-02"
	var ouvrirait: String = jeu._scene_demandee()
	print("REJEU demandé i-02 → le jeu ouvrirait « %s », consommé : %s, rien ne se note : %s" % [
		ouvrirait, Partie.rejoue == "", jeu._libre])

	_touche("pause")
	await _attendre(4)
	print("CHAPITRES refermés, pause rendue : %s" % (
		not jeu._ui.chapitres_visible() and jeu._en_pause))


## Le sac, ses deux catégories, et ce que porter change.
##
## Ce qu'on mesure n'est pas qu'un écran s'ouvre : c'est qu'une pièce portée
## descende jusqu'aux nombres du combat. Une statistique qui ne bouge que dans
## le tableau est une décoration.
func _eprouver_le_sac() -> void:
	await _descendre_jusqu_a("Sac")
	_touche("ui_accept")
	await _attendre(6)
	jeu.get_viewport().get_texture().get_image().save_png("res://capture-sac.png")
	print("SAC « %s » : %d entrée(s)" % [
		jeu.CATEGORIES_SAC[jeu._categorie_sac], jeu._contenu_sac.size()])

	_touche("ui_right")
	await _attendre(6)
	print("SAC « %s » : %d entrée(s)" % [
		jeu.CATEGORIES_SAC[jeu._categorie_sac], jeu._contenu_sac.size()])
	jeu.get_viewport().get_texture().get_image().save_png("res://capture-sac-equipements.png")

	var stats_avant: Dictionary = jeu._stats.duplicate()
	var vitesse_avant: float = jeu._vitesse()
	var epee_avant: int = jeu._degats_epee()
	var vie_avant: int = jeu._wellan.vie_max

	# On porte tout ce qui se porte, une entrée après l'autre.
	for i in jeu._contenu_sac.size():
		jeu._choix_sac = i
		jeu._rafraichir_le_sac()
		await _attendre(2)
		if i < jeu._contenu_sac.size() and not bool(jeu._contenu_sac[i]["porte"]):
			_touche("ui_accept")
			await _attendre(4)
	await _attendre(4)
	jeu.get_viewport().get_texture().get_image().save_png("res://capture-sac-porte.png")

	print("SAC porté : %s" % [Partie.equipe()])
	print("STATS avant : %s" % [stats_avant])
	print("STATS après : %s" % [jeu._stats])
	print("STATS vitesse %.0f → %.0f px/s | épée %d → %d | vie %d → %d | réduction %d" % [
		vitesse_avant, jeu._vitesse(), epee_avant, jeu._degats_epee(),
		vie_avant, jeu._wellan.vie_max, jeu._reduction()])
	print("STATS le combattant en tient compte : reduction=%d, vie_max=%d" % [
		jeu._wellan.reduction, jeu._wellan.vie_max])

	_touche("pause")
	await _attendre(4)
	print("SAC refermé, pause rendue : %s" % (not jeu._ui.sac_visible() and jeu._en_pause))

	# Et la vitesse doit être descendue jusqu'aux pieds, non seulement au tableau.
	await _eprouver_la_course()


## Joue un chapitre, et rien d'autre.
##
## Le parcours complet éprouve le tour du Château, la musique, la course, le
## sac, les commandes, les orientations, la pause. C'est utile une fois ; c'est
## ruineux à chaque chapitre écrit, et le jeu va continuer de s'étoffer.
##
## Ce mode-ci ne répond qu'à une question : **ce chapitre se joue-t-il jusqu'au
## bout, et qu'est-ce qui manque ?** Il ne saisit aucune image, donc il tourne
## sans fenêtre. Il rend une ligne unique, faite pour être lue par un script
## autant que par un humain.
func _verifier() -> void:
	rapide = true
	var depart := Time.get_ticks_msec()

	jeu._ui.fermer_carton()
	jeu._reciter(jeu._scene.get("ouverture", []))
	var patience := 0
	while jeu._ouverte and patience < 60:
		_touche("ui_accept")
		await _attendre(2)
		patience += 1

	var absents := PackedStringArray()
	var etapes := 0
	var garde := 0
	while not jeu._ui.acheve_visible() and garde < 40:
		garde += 1
		var etape: Dictionary = jeu._etape_courante()
		var attend: Dictionary = etape.get("attend", {})

		if attend.has("vague_defaite"):
			for e in jeu._ennemis:
				if not is_instance_valid(e["noeud"]):
					continue
				var qui: Combattant = e["noeud"]
				while is_instance_valid(qui) and qui.vivant():
					qui.encaisser(99, "fer")
					await _attendre(4)
			await _attendre(20)
			etapes += 1
			continue

		var cibles := PackedStringArray()
		if attend.has("parler"):
			cibles.append(str(attend["parler"]))
		elif attend.has("parler_tous"):
			for id in attend["parler_tous"]:
				cibles.append(str(id))
		else:
			break

		for id in cibles:
			if not jeu._habitants.has(id):
				absents.append(id)
				continue
			await _parler_a(id, "")
		etapes += 1

	# Ce qui reste à entendre après la clôture : beaucoup de répliques ne sont
	# exigées par aucun objectif, et c'est voulu — mais zéro signalerait qu'on
	# n'a rien écrit d'autre que le strict nécessaire.
	jeu._rafraichir_les_bulles()
	await _attendre(2)
	var reste := 0
	for id in jeu._habitants:
		if not str(id).begins_with("objet:") and jeu._a_dire(str(id)):
			reste += 1

	var acheve: bool = jeu._ui.acheve_visible()

	# On coupe la passe de physique avant de quitter. `quit()` libère les nœuds
	# à la fin de l'image, et la passe suivante appelait encore `_ui.jauges()`
	# sur une interface déjà partie — une erreur d'extinction, sans rapport avec
	# le chapitre, mais que le relevé d'erreurs prenait au sérieux.
	jeu.set_physics_process(false)

	print("RAPIDE %s | %s | etapes=%d | absents=%s | reste=%d | %.1fs" % [
		jeu._chapitre,
		"achevé" if acheve else "PAS ACHEVÉ",
		etapes,
		"aucun" if absents.is_empty() else ",".join(absents),
		reste,
		(Time.get_ticks_msec() - depart) / 1000.0])
	jeu.get_tree().quit()


## Le tour des salles, porte après porte.
##
## Ce qu'on éprouve n'est pas qu'une porte s'ouvre : c'est qu'elle ramène, et
## que la salle qu'on retrouve est celle qu'on a laissée. Un décor dont on ne
## peut pas sortir et un décor qui se rebâtit sans ce qu'il contenait se
## ressemblent beaucoup, vus du fichier.
##
## Et le banc rend ce qu'il emprunte : il repart de la salle où le chapitre se
## joue, faute de quoi tout ce qui suit parlerait à des absents.
func _visiter_les_salles() -> void:
	var depart: String = jeu._salle_id
	var vues := {}
	await _visiter(depart, vues, 0)
	print("SALLES %d visitée(s) : %s" % [vues.size(), vues.keys()])
	if jeu._salle_id == depart:
		print("SALLES retour rendu : %s" % depart)
	else:
		print("SALLES RETOUR MANQUÉ : resté en %s au lieu de %s" % [jeu._salle_id, depart])


func _visiter(ici: String, vues: Dictionary, profondeur: int) -> void:
	vues[ici] = true
	print("SALLE %s — « %s », %d objet(s), %d porte(s)" % [
		ici, jeu._salle.get("nom", "?"), jeu._objets.size(), jeu._passages.size()])

	if profondeur > 0:
		# Au milieu du plancher : une salle ne se juge pas sur une capture
		# centrée à deux tuiles du personnage.
		jeu._wellan.global_position = Vector2(jeu._taille()) * jeu.TUILE / 2.0
		await _attendre(10)
		jeu.get_viewport().get_texture().get_image().save_png("res://capture-salle-%s.png" % ici)

	await _vider_les_coffres(ici)

	# Trois niveaux, depuis que la bibliothèque dessert la chambre de Kira :
	# trône → galerie → bibliothèque → chambre. À deux, la porte de la chambre
	# n'était jamais poussée, et son verrou ne s'éprouvait pas.
	if profondeur >= 3:
		return

	for cle in jeu._passages.keys():
		var vers := str(jeu._passages[cle]["vers"])
		if vues.has(vers):
			continue
		if not await _franchir_la_porte(str(cle)):
			continue
		await _visiter(vers, vues, profondeur + 1)

		var retour := ""
		for c in jeu._passages:
			if str(jeu._passages[c]["vers"]) == ici:
				retour = str(c)
		if retour == "" or not await _franchir_la_porte(retour):
			print("SALLE %s : pas de retour vers %s" % [vers, ici])
			return


func _franchir_la_porte(cle: String) -> bool:
	var porte: Dictionary = jeu._passages.get(cle, {})
	if porte.is_empty():
		print("PORTE inconnue : %s" % cle)
		return false

	var avant: String = jeu._salle_id
	var vers := str(porte["vers"])
	jeu._wellan.global_position = Vector2(porte["case"]) * jeu.TUILE

	# Une porte que le chapitre n'a pas encore ouverte : on la pousse quand même.
	# Annoncer qu'elle est fermée ne prouve rien ; ce qui compte est qu'elle
	# refuse quand on appuie.
	if jeu._verrouillee(porte):
		var patience_v := 0
		while jeu._proche != cle and patience_v < 120:
			await jeu.get_tree().process_frame
			patience_v += 1
		# L'image avant d'appuyer : c'est le seul moment où l'on voit à la fois
		# le battant grisé et l'invite qui dit « Fermée ».
		if not rapide:
			await _attendre(3)
			jeu.get_viewport().get_texture().get_image().save_png("res://capture-porte-fermee.png")
			print("PORTE fermée, invite « %s »" % jeu._ui.invite_affichee())
		_touche("ui_accept")
		await _attendre(6)
		print("PORTE VERROUILLÉE %s → %s : %s (invite « %s »)" % [
			cle, vers, "refuse" if jeu._salle_id == avant else "A CÉDÉ",
			jeu._ui.invite_affichee()])
		while jeu._ouverte:
			_touche("ui_accept")
			await _attendre(2)
		return false

	# On attend que le jeu propose la porte au lieu de compter les images : la
	# zone répond quand la physique la fait répondre, et au démarrage la
	# compilation des shaders l'affame.
	var patience := 0
	while jeu._proche != cle and patience < 150:
		await jeu.get_tree().process_frame
		patience += 1
	if jeu._proche != cle:
		print("PORTE hors de portée : %s → %s (proche = « %s »)" % [cle, vers, jeu._proche])
		return false

	# Wellan devant la porte, l'invite allumée : c'est la seule image qui montre
	# à la fois que la porte se voit et qu'elle dit où elle mène. Deux images
	# d'attente, le tampon dessiné ayant un tour de retard sur l'état.
	await _attendre(3)
	jeu.get_viewport().get_texture().get_image().save_png("res://capture-porte-%s.png" % avant)
	print("PORTE %s invite « %s »" % [cle, jeu._ui.invite_affichee()])
	_touche("ui_accept")
	await _attendre(6)
	if jeu._salle_id != vers:
		print("PORTE SANS EFFET : %s → %s, resté en %s" % [cle, vers, jeu._salle_id])
		return false
	print("PORTE franchie : %s → %s, arrivée en %s, bandeau « %s »" % [
		avant, vers, jeu._wellan.position / float(jeu.TUILE), jeu._ui.lieu_affiche()])
	return true


## La musique, et surtout sa boucle.
##
## Un morceau qui joue s'entend ; un morceau qui s'arrête au bout de quarante
## secondes au lieu de reprendre ne s'entend qu'au bout de quarante secondes, et
## seulement si l'on est resté à écouter. On ne l'attend donc pas : on pose la
## tête de lecture juste avant la fin et l'on regarde si elle revient au début.
func _eprouver_la_musique() -> void:
	var declarees: Array = jeu._monde.get("musiques", [])
	var ici: String = jeu._sons.morceau()
	print("MUSIQUE %d déclarée(s) ; dans « %s » : %s" % [
		declarees.size(), jeu._salle.get("lieu", "?"),
		"« %s »" % ici if ici != "" else "aucune, ce lieu est muet"])
	if ici == "":
		return

	var duree := 0.0
	for m in declarees:
		if str((m as Dictionary).get("nom", "")) == ici:
			duree = float((m as Dictionary).get("duree", 0.0))

	var avant: float = jeu._sons.ou_en_est()
	await _attendre(40)
	var apres: float = jeu._sons.ou_en_est()
	print("MUSIQUE avance : %.2fs → %.2fs sur %.2fs" % [avant, apres, duree])

	jeu._sons.avancer_a(maxf(duree - 0.25, 0.0))
	await _attendre(70)
	var reprise: float = jeu._sons.ou_en_est()
	var joue_encore: bool = jeu._sons.morceau() != ""
	print("MUSIQUE passé la fin : %s, position %.2fs — %s" % [
		"joue encore" if joue_encore else "ARRÊTÉE",
		reprise,
		"boucle" if joue_encore and reprise < duree * 0.5 else "NE BOUCLE PAS"])


## La course, mesurée.
##
## Une vitesse ne se voit pas sur une capture : deux images d'un personnage au
## même endroit ne disent pas à quelle allure il y est arrivé. On mesure donc le
## chemin parcouru en un même nombre d'images, au pas puis à la course, et l'on
## compare le rapport à celui qu'annoncent les constantes.
func _eprouver_la_course() -> void:
	# On rend la main au jeu avant de mesurer : appelée après l'épreuve du sac,
	# cette mesure tournait pendant que le menu était encore ouvert, et Wellan
	# ne bougeait pas d'un pixel. Le banc concluait qu'il était bloqué.
	jeu._ui.fermer_carton()
	jeu._ui.pause(false)
	jeu._en_pause = false
	jeu._ouverte = false
	# Le coin haut-gauche : dégagé dans toutes les salles écrites à ce jour, là
	# où le milieu porte du mobilier ou six Chevaliers.
	var depart: Vector2 = Vector2(2, 2) * jeu.TUILE

	var chemins := {}
	for essai in [["pas", false], ["course", true]]:
		jeu._wellan.global_position = depart
		await _attendre(6)
		var avant: Vector2 = jeu._wellan.global_position
		if bool(essai[1]):
			_maintenir("courir", true)
		_maintenir("ui_right", true)
		await _attendre(30)
		_maintenir("ui_right", false)
		if bool(essai[1]):
			_maintenir("courir", false)
		chemins[essai[0]] = jeu._wellan.global_position.distance_to(avant)
		await _attendre(6)

	var au_pas: float = chemins["pas"]
	if au_pas < 10.0:
		print("COURSE : Wellan n'a pas avancé (%.0f px) — quelque chose le bloque" % au_pas)
		return
	print("COURSE %.0f px au pas, %.0f px en courant — rapport %.2f, attendu %.2f" % [
		au_pas, chemins["course"], chemins["course"] / au_pas,
		jeu.VITESSE_COURSE / jeu.VITESSE])


## Maintient ou relâche une action, au lieu de la taper.
##
## `_touche` envoie une pression et son relâchement dans la même image, ce qui
## convient pour parler ou frapper. Courir se tient.
func _maintenir(action: String, tenu: bool) -> void:
	var t := InputEventAction.new()
	t.action = action
	t.pressed = tenu
	Input.parse_input_event(t)


## L'écran des commandes.
##
## Deux choses se mesurent : que chaque entrée déclarée existe bel et bien dans
## la table d'entrées du moteur — une commande renommée ou retirée laisserait
## l'aide mentir en silence — et que l'écran s'ouvre puis se referme. Ce qu'elle
## montre, en revanche, se regarde sur la capture.
func _eprouver_les_commandes() -> void:
	var orphelines := PackedStringArray()
	for c in jeu.COMMANDES:
		var action := str((c as Dictionary).get("action", ""))
		if not InputMap.has_action(action) or InputMap.action_get_events(action).is_empty():
			orphelines.append(action)
	print("COMMANDES %d ligne(s)%s" % [
		jeu.COMMANDES.size(),
		"" if orphelines.is_empty() else " — SANS TOUCHE : %s" % [orphelines]])

	if not jeu._aux_commandes:
		print("COMMANDES pas montrées au départ (déjà vues dans ce carnet)")
		return
	await _attendre(6)
	jeu.get_viewport().get_texture().get_image().save_png("res://capture-commandes.png")
	_touche("ui_accept")
	await _attendre(6)
	print("COMMANDES refermées : %s, jeu rendu : %s" % [
		not jeu._ui.commandes_visible(), not jeu._en_pause])


## Les commandes rouvertes depuis le menu, et le menu rendu ensuite.
func _eprouver_les_commandes_du_menu() -> void:
	await _descendre_jusqu_a("Commandes")
	_touche("ui_accept")
	await _attendre(6)
	jeu.get_viewport().get_texture().get_image().save_png("res://capture-commandes-menu.png")
	print("COMMANDES depuis le menu : ouvertes %s" % jeu._ui.commandes_visible())
	_touche("ui_accept")
	await _attendre(6)
	print("COMMANDES refermées, pause rendue : %s" % jeu._en_pause)


## Descend jusqu'à une entrée du menu, désignée par son nom.
##
## Compter les appuis liait le banc à l'ordre du menu : le jour où « Codex »
## s'est intercalé en deuxième position, un seul appui ne menait plus à
## « Sauvegarder » — et le test aurait continué à passer en éprouvant autre
## chose.
func _descendre_jusqu_a(entree: String) -> void:
	for i in jeu.CHOIX_PAUSE.size():
		if jeu.CHOIX_PAUSE[jeu._choix_pause] == entree:
			return
		_touche("ui_down")
		await _attendre(2)
	push_error("Entrée de pause introuvable : %s" % entree)


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

	await _eprouver_le_combat_sonore()
	await _eprouver_les_sons()

	jeu.get_tree().quit()


## Les bruitages de mêlée, par le chemin d'un vrai joueur.
##
## Les appeler directement prouverait que le fichier se joue, non que le jeu le
## joue au bon moment. On passe donc par la touche — `Input.parse_input_event`,
## comme partout ailleurs dans ce banc — et l'on relève le compteur avant et
## après. Ce qui n'a pas bougé n'est pas branché.
func _eprouver_le_combat_sonore() -> void:
	# Wellan est peut-être encore à terre du relèvement précédent.
	jeu._vaincu = false
	jeu._wellan.vie = jeu.VIE_WELLAN
	jeu._vie_dodue = float(jeu.VIE_WELLAN)
	jeu._energie = jeu.ENERGIE_MAX

	# Le banc des effets tourne à la première étape, où la vague n'est pas encore
	# levée. On la fait lever par la fonction du jeu — non en posant des
	# adversaires à la main : ce qu'on éprouve doit passer par le chemin normal.
	if jeu._vague_debout() == 0:
		for etape in jeu._etapes():
			if not (etape as Dictionary).get("vague", []).is_empty():
				jeu._lever_la_vague(etape)
				await _attendre(10)
				break
	if jeu._vague_debout() == 0:
		print("COMBAT SONORE : ce chapitre ne lève aucune vague, épreuve sautée")
		return

	var carapace: Combattant = null
	var chair: Combattant = null
	for e in jeu._ennemis:
		if not is_instance_valid(e["noeud"]):
			continue
		var qui: Combattant = e["noeud"]
		if not qui.vivant():
			continue
		if qui.immunise_magie and carapace == null:
			carapace = qui
		elif not qui.immunise_magie and chair == null:
			chair = qui
	var cible: Combattant = carapace if carapace != null else chair
	if cible == null:
		print("COMBAT SONORE : aucun adversaire debout, épreuve sautée")
		return

	# Le fer qui entre, puis l'adversaire qui tombe. On frappe jusqu'à ce qu'il
	# cède : le répit entre deux coups fait qu'un seul ne suffit pas.
	var avant := int(jeu._sons.joues.get("fer-touche", 0))
	jeu._wellan.global_position = cible.global_position + Vector2(0, jeu.TUILE)
	jeu._direction = "nord"
	# Trente images entre deux coups, non huit. `Combattant` accorde un répit de
	# 0,45 s après chaque blessure : à huit images on frappait dans le répit,
	# douze coups ne portaient que deux fois, et l'adversaire ne tombait jamais
	# — donc « ennemi-meurt » ne partait pas et l'on aurait pu croire le son
	# débranché alors qu'il l'était très bien.
	# `is_instance_valid` d'abord : l'adversaire qui tombe se libère lui-même
	# dans son signal `peri`, et l'appel suivant sur la référence gardée lève
	# « Nonexistent function 'vivant' in base 'previously freed' ». L'erreur
	# interrompait la suite de l'épreuve sans rien faire échouer : les deux sons
	# de sort n'étaient plus éprouvés du tout, et le relevé final les donnait
	# quand même pour partis, puisque le rattrapage les jouait directement.
	var coups := 0
	while is_instance_valid(cible) and cible.vivant() and coups < 10:
		jeu._prochain_coup = 0.0
		_touche("frapper")
		await _attendre(30)
		coups += 1
	print("COMBAT SONORE fer : %d coup(s), « fer-touche » %d → %d, « ennemi-meurt » %d" % [
		coups, avant, int(jeu._sons.joues.get("fer-touche", 0)),
		int(jeu._sons.joues.get("ennemi-meurt", 0))])

	# La carapace qui refuse le sort. Le texte l'impose : le fer, pas la magie.
	var insecte: Combattant = null
	for e in jeu._ennemis:
		if not is_instance_valid(e["noeud"]):
			continue
		var qui: Combattant = e["noeud"]
		if qui.vivant() and qui.immunise_magie:
			insecte = qui
			break
	if insecte != null and is_instance_valid(insecte):
		jeu._wellan.global_position = insecte.global_position + Vector2(-70, 0)
		jeu._direction = "est"
		jeu._energie = jeu.ENERGIE_MAX
		_touche("lancer")
		await _attendre(60)
		print("COMBAT SONORE carapace : « sort-glisse » %d, « sort-touche » %d" % [
			int(jeu._sons.joues.get("sort-glisse", 0)),
			int(jeu._sons.joues.get("sort-touche", 0))])
	else:
		print("COMBAT SONORE : plus d'homme-insecte debout pour éprouver la carapace")

	# Et le sort qui prend, sur ce qui n'a pas de carapace. Les dragons brûlent :
	# c'est l'autre moitié de la règle que le texte impose, et elle a son son.
	# La première vague de Zénor n'est faite que d'hommes-insectes, tous
	# carapacés : il n'y a rien à brûler tant qu'on n'appelle pas la vague qui
	# porte des dragons. On la cherche par les espèces de la scène plutôt que
	# par son rang, un rang étant ce qui change quand on réécrit un chapitre.
	var brulable: Combattant = null
	for essai in 2:
		for e in jeu._ennemis:
			if not is_instance_valid(e["noeud"]):
				continue
			var qui: Combattant = e["noeud"]
			if qui.vivant() and not qui.immunise_magie:
				brulable = qui
				break
		if brulable != null or essai > 0:
			break
		var especes: Dictionary = jeu._scene.get("especes", {})
		for etape in jeu._etapes():
			var trouvee := false
			for groupe in (etape as Dictionary).get("vague", []):
				var espece: Dictionary = especes.get(str(groupe["espece"]), {})
				if not bool(espece.get("immunise_magie", false)):
					trouvee = true
			if trouvee:
				jeu._lever_la_vague(etape)
				await _attendre(10)
				break
	if brulable != null and is_instance_valid(brulable):
		jeu._wellan.global_position = brulable.global_position + Vector2(-70, 0)
		jeu._direction = "est"
		jeu._energie = jeu.ENERGIE_MAX
		_touche("lancer")
		await _attendre(60)
		print("COMBAT SONORE chair : « sort-touche » %d" % [
			int(jeu._sons.joues.get("sort-touche", 0))])
	else:
		print("COMBAT SONORE : rien de brûlable debout")

	# Et le coup reçu : on se colle à un adversaire et on le laisse frapper.
	var frappeur: Combattant = null
	for e in jeu._ennemis:
		if is_instance_valid(e["noeud"]) and (e["noeud"] as Combattant).vivant():
			frappeur = e["noeud"]
			break
	if frappeur != null and is_instance_valid(frappeur):
		jeu._wellan.global_position = frappeur.global_position + Vector2(0, 10)
		await _attendre(120)
		print("COMBAT SONORE griffe : « griffe » %d, vie de Wellan %d" % [
			int(jeu._sons.joues.get("griffe", 0)), jeu._wellan.vie])
	else:
		print("COMBAT SONORE : plus personne pour frapper Wellan")


## Les bruitages, dont aucune capture ne dira jamais rien.
##
## C'est le seul élément du jeu qu'une image ne montre pas. Un fichier absent,
## un import non fait, un nom mal orthographié : le jeu se tait, et l'on croit
## simplement qu'il est discret. La règle du projet veut qu'on regarde ce qu'une
## machine ne peut pas juger — ici c'est l'inverse, il n'y a rien à regarder, et
## la mesure est tout ce qu'on a.
##
## Deux choses se mesurent : que chacun se charge, et que chacun parte au moins
## une fois. Un bruitage écrit, produit, versionné et jamais joué dormirait dans
## le dépôt sans que rien ne le signale.
func _eprouver_les_sons() -> void:
	var attendus: Array = jeu._monde.get("sons", [])
	print("SONS %d déclaré(s), %d chargé(s)%s" % [
		attendus.size(), jeu._sons.charges(),
		"" if jeu._sons.manquants.is_empty() else " — MANQUANTS %s" % [jeu._sons.manquants]])
	print("SONS partis pendant les effets : %s" % [jeu._sons.joues])

	# Ce que le parcours visuel n'a pas déclenché, on le déclenche ici. Ce qui
	# reste à zéro après cela n'a pas pu être joué du tout.
	for nom in attendus:
		if not jeu._sons.joues.has(nom):
			jeu._sons.jouer(str(nom))
			await _attendre(3)

	var muets := PackedStringArray()
	for nom in attendus:
		if int(jeu._sons.joues.get(nom, 0)) == 0:
			muets.append(str(nom))
	print("SONS %s" % ("tous partis au moins une fois" if muets.is_empty()
		else "JAMAIS PARTIS : %s" % [muets]))


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
		if attente == 24 and not rapide:
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
	if jeu._bulles.size() >= 3 and not jeu._bulles_capture and not rapide:
		jeu._bulles_capture = true
		await _attendre(3)
		jeu.get_viewport().get_texture().get_image().save_png("res://capture-bulles.png")
		print("BULLES %d à l'écran" % jeu._bulles.size())

	# Une image avant d'ouvrir : c'est le seul moment où l'invite se voit, et
	# elle est là pour être vue.
	if not jeu._invite_capture and not rapide:
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
		if pages == 2 and jeu._ouverte and not rapide:
			jeu.get_viewport().get_texture().get_image().save_png("res://capture-%s.png" % nom_image)
		# Et une image dès qu'une description paraît : c'est l'autre affichage,
		# et rien ne prouverait autrement qu'il s'ouvre.
		# Une image quand Wellan parle : son portrait est le plus vu du jeu.
		if jeu._ouverte and not jeu._wellan_capture and not rapide and jeu._page < jeu._pages.size() \
			and str((jeu._pages[jeu._page] as Dictionary).get("qui", "")) == "wellan":
			jeu._wellan_capture = true
			jeu.get_viewport().get_texture().get_image().save_png("res://capture-wellan-parle.png")
		if jeu._ui.recit_visible() and not jeu._recit_capture and not rapide:
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
	if not rapide:
		print("PARLE %s en %d pages, regarde vers %s" % [id, pages, tourne])


func _garder(nom: String, images: int) -> void:
	await _attendre(images)
	jeu.get_viewport().get_texture().get_image().save_png("res://capture-%s.png" % nom)
