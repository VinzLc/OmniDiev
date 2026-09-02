extends Node
##
## Tout ce que le jeu fait entendre.
##
## Le jeu dit `jouer("epee")`. Combien de lecteurs existent, lequel est libre, à
## quel volume et sur quel bus — cela ne le regarde pas. C'est le partage qui a
## déjà servi pour l'interface, et pour la même raison : le jour où il faudra un
## réglage de volume ou une musique, rien de tout cela ne remontera dans
## `main.gd`.
##
## Les bruitages sont **calculés**, non enregistrés : `lib/sons.ts` les écrit à
## la production, comme il dessine les arcs de taillade. Un coup d'épée est une
## enveloppe sur du bruit, ce qui est une forme exacte.

const DOSSIER := "res://donnees/sons/"
const MUSIQUES := "res://donnees/musiques/"

## Huit lecteurs.
##
## Un coup qui tue en touchant fait déjà deux sons dans la même image — le fer
## qui entre, l'adversaire qui tombe — et la vague en compte plusieurs. À un
## seul lecteur, chaque son couperait le précédent, ce qui s'entend précisément
## au moment où il y a le plus à écouter.
const LECTEURS := 8

var _flux := {}
var _lecteurs: Array[AudioStreamPlayer] = []
var _tour := 0

## Ce que le banc relève.
##
## Un son ne se voit pas sur une capture. Un fichier manquant, un import non
## fait, un nom mal orthographié : rien de tout cela ne se remarque en jouant,
## on croit simplement que le jeu est discret. Ces deux relevés sont la seule
## prise mécanique qu'on ait dessus.
var manquants: Array[String] = []
var joues := {}

var _musicien: AudioStreamPlayer
var _images := {}    ## par morceau, sa longueur — d'où la fin de boucle
var _joue := ""      ## le morceau en cours


func _init(noms: Array = [], morceaux: Array = []) -> void:
	for m in morceaux:
		_images[str((m as Dictionary).get("nom", ""))] = int((m as Dictionary).get("images", 0))

	for nom in noms:
		var chemin := DOSSIER + str(nom) + ".wav"
		var flux = load(chemin)
		if flux == null:
			manquants.append(str(nom))
			push_error("Bruitage introuvable : %s — lancer npm run jeu:donnees" % chemin)
			continue
		_flux[str(nom)] = flux

	# Les lecteurs se posent ici et non dans `_ready` : un son demandé avant que
	# le nœud soit entré dans l'arbre ne trouverait personne pour le jouer.
	for i in LECTEURS:
		var lecteur := AudioStreamPlayer.new()
		add_child(lecteur)
		_lecteurs.append(lecteur)

	# La musique a son propre lecteur : elle dure, là où les bruitages passent.
	# La faire tourner dans le même tourniquet la ferait couper par le premier
	# coup d'épée.
	_musicien = AudioStreamPlayer.new()
	add_child(_musicien)


## Joue un bruitage, au premier lecteur libre.
##
## Le tourniquet part du dernier servi et prend le premier qui ne joue pas :
## couper un son encore en cours pour en lancer un autre s'entend, et cela
## s'entend surtout dans la bousculade, qui est le moment où l'on écoute.
func jouer(nom: String, volume_db := 0.0) -> void:
	var flux = _flux.get(nom)
	if flux == null:
		return
	joues[nom] = int(joues.get(nom, 0)) + 1

	var choisi: AudioStreamPlayer = _lecteurs[_tour]
	for i in LECTEURS:
		var candidat := _lecteurs[(_tour + i) % LECTEURS]
		if not candidat.playing:
			choisi = candidat
			_tour = (_tour + i + 1) % LECTEURS
			break
	choisi.stream = flux
	choisi.volume_db = volume_db
	choisi.play()


## Combien de bruitages sont prêts.
func charges() -> int:
	return _flux.size()


## Met une musique — ou la laisse courir si c'est déjà la bonne.
##
## Le nom suffit à décider. Relancer le morceau à chaque porte franchie
## couperait la phrase en cours et ferait entendre le Château comme quatre
## salles au lieu d'un seul lieu.
##
## Un nom qu'aucun fichier ne porte vaut silence, sans erreur : c'est ainsi
## qu'un lieu sans musique est un lieu sans musique. La forêt et la grève n'en
## ont pas encore, et il ne faut pas qu'elles héritent de celle du Château.
func musique(nom: String, volume_db := -8.0) -> void:
	if nom != "" and not _images.has(nom):
		nom = ""
	if nom == "":
		taire()
		return
	if nom == _joue and _musicien.playing:
		return

	var flux = load(MUSIQUES + nom + ".wav")
	if flux == null:
		push_error("Musique introuvable : %s%s.wav" % [MUSIQUES, nom])
		return

	# Les points de boucle se posent ici, non dans le fichier d'import.
	#
	# Ils s'expriment en images, et le nombre d'images vient de la production
	# qui a rendu le morceau — le déduire des octets marcherait tant que
	# l'import ne compresse pas, et cesserait de marcher le jour où il le fait,
	# sans rien signaler d'autre qu'une boucle au mauvais endroit.
	var longueur := int(_images.get(nom, 0))
	if flux is AudioStreamWAV and longueur > 0:
		flux.loop_mode = AudioStreamWAV.LOOP_FORWARD
		flux.loop_begin = 0
		flux.loop_end = longueur

	_musicien.stream = flux
	_musicien.volume_db = volume_db
	_musicien.play()
	_joue = nom


func taire() -> void:
	if _joue == "":
		return
	_musicien.stop()
	_joue = ""


## La musique s'arrête avec le jeu, les bruitages non : ceux-ci sont déjà finis.
func suspendre(oui: bool) -> void:
	_musicien.stream_paused = oui


## Ce que le banc relève : le morceau en cours, et où il en est.
func morceau() -> String:
	return _joue if _musicien.playing else ""


func ou_en_est() -> float:
	return _musicien.get_playback_position() if _musicien.playing else -1.0


## Déplace la tête de lecture. Le banc s'en sert pour éprouver le bouclage sans
## attendre quarante secondes ; le jeu n'en a pas l'usage.
func avancer_a(secondes: float) -> void:
	if _musicien.playing:
		_musicien.seek(secondes)
