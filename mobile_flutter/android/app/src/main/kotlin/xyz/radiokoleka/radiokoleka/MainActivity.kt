package xyz.radiokoleka.app

import com.ryanheise.audioservice.AudioServiceActivity

// `AudioServiceActivity` et non `FlutterActivity` : c'est elle qui rattache
// l'app au service de lecture, pour qu'un appui sur la notification revienne
// ici au lieu d'ouvrir une seconde instance.
class MainActivity : AudioServiceActivity()
