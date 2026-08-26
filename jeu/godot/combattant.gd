class_name Combattant extends CharacterBody2D
##
## Ce qui peut frapper et être frappé.
##
## Wellan et ses adversaires partagent cette base, parce qu'ils obéissent aux
## mêmes règles : on ne subit pas deux coups dans le même souffle, et l'on meurt
## à zéro. Ce qui les distingue n'est pas la nature mais les nombres — et une
## propriété, tirée du texte : les hommes-insectes portent une carapace « les
## rendant invulnérables à la magie ». Ce n'est pas un équilibrage, c'est une
## donnée du récit.

signal blesse(reste: int, sur: int)
signal peri

@export var vie_max := 6
@export var immunise_magie := false
@export var camp := "ennemi"

var vie := 6
var _repit := 0.0   ## instant jusqu'auquel les coups ne portent plus


func _ready() -> void:
	vie = vie_max


## Encaisse un coup. Rend vrai si le coup a porté.
func encaisser(degats: int, genre: String) -> bool:
	if vie <= 0:
		return false
	# La carapace : la magie glisse dessus sans l'entamer.
	if genre == "magie" and immunise_magie:
		return false
	var maintenant := Time.get_ticks_msec() / 1000.0
	if maintenant < _repit:
		return false

	vie -= degats
	# Un bref répit après chaque coup, sans quoi un adversaire au contact vide
	# une barre de vie en une fraction de seconde et l'on ne peut rien y faire.
	_repit = maintenant + 0.45
	blesse.emit(vie, vie_max)
	if vie <= 0:
		peri.emit()
	return true


func vivant() -> bool:
	return vie > 0
