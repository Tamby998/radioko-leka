# Construction de l app macOS sans Xcode.
#
# Les Command Line Tools suffisent : swiftc compile, codesign signe en ad-hoc,
# et le bundle est assemble a la main. Verifie — un .app complet pese 52 Ko a
# vide, et rien ici n exige les 15 Go d Xcode.

NOM     = RadiokoLeka
SOURCES = $(wildcard Hira/Sources/*.swift)
BUNDLE  = build/$(NOM).app
MACOS   = $(BUNDLE)/Contents/MacOS
RES     = $(BUNDLE)/Contents/Resources
# macOS 13 et non 14 : deux appels a `onChange` a deux arguments, et rien
# d autre, exigeaient Sonoma. Les ramener a la forme a un argument a rendu
# l app installable sur les Mac restes a Ventura — ceux de 2017, que 14
# refuse. Compile pour 13 ; jamais execute sur 13, faute de machine.
MIN     = 13.0
CADRES  = -framework WebKit -framework Network -framework AppKit -framework AVFoundation -framework MediaPlayer

VERSION = 0.1.0

.PHONY: tout lancer universel banc tests dmg propre

tout: $(BUNDLE)

# Image disque a donner.
#
# Un dossier compresse marcherait, mais le .dmg porte deux choses qu une
# archive ne porte pas : le lien vers Applications, qui dit quoi faire sans
# l expliquer, et le Lisez-moi, qu on lira parce qu il est la et pas dans un
# message.
#
# `hdiutil` fait partie de macOS : pas d outil a installer.
#
# **Pas de dependance sur $(BUNDLE)** : elle faisait reconstruire le bundle a
# l architecture de la machine, ecrasant la version universelle qu on venait
# de produire. `make universel dmg` rendait donc un dmg x86_64 seul.
#
#   make tout dmg        # l architecture de cette machine
#   make universel dmg   # les deux, a donner
dmg:
	@test -d $(BUNDLE) || { echo "  construis d abord : make tout, ou make universel"; exit 1; }
	@STAGE=$$(mktemp -d) && \
	cp -R $(BUNDLE) "$$STAGE/" && \
	ln -s /Applications "$$STAGE/Applications" && \
	cp dmg/Lisez-moi.txt "$$STAGE/" && \
	hdiutil create -volname "$(NOM)" -srcfolder "$$STAGE" -ov -quiet \
	  -format UDZO build/$(NOM)-$(VERSION).dmg && \
	echo "  build/$(NOM)-$(VERSION).dmg — $$(du -h build/$(NOM)-$(VERSION).dmg | cut -f1)" && \
	lipo -archs $(MACOS)/$(NOM) | sed 's/^/  architectures : /'

# Tests de la logique pure. Pas de XCTest, pas d Xcode : un binaire qui affirme
# et qui sort non nul si quelque chose casse, comme le banc.
#
# Il compile toutes les sources sauf `main.swift`, dont le code de premier
# niveau entrerait en conflit avec celui des tests.
SOURCES_SANS_MAIN = $(filter-out Hira/Sources/main.swift,$(SOURCES))

tests: build/tests
	@build/tests

build/tests: tests/main.swift $(SOURCES_SANS_MAIN)
	@mkdir -p build
	swiftc -O $(CADRES) -o build/tests tests/main.swift $(SOURCES_SANS_MAIN)

# Banc d integration. Il remplace celui qui tournait dans un navigateur : un
# onglet masque fait brider les minuteries, et une passe menee ainsi avait
# declare 50 titres gasy injouables alors que 74 sur 76 jouent.
#
#   make banc C=../web/outils/candidats.json V=../web/outils/verdicts.json
banc: banc/banc
	@cd banc && ./banc $(or $(C),../../web/outils/candidats.json) \
	                   $(or $(V),../../web/outils/verdicts.json)

banc/banc: banc/main.swift Hira/Sources/ServeurLocal.swift Hira/Ressources/lecteur.html
	swiftc -O $(CADRES) -o banc/banc banc/main.swift Hira/Sources/ServeurLocal.swift

$(BUNDLE): $(SOURCES) Hira/Ressources/lecteur.html Hira/Info.plist Hira/Ressources/logo/RadiokoLeka.icns
	@mkdir -p $(MACOS) $(RES)
	swiftc -O $(CADRES) -o $(MACOS)/$(NOM) $(SOURCES)
	@cp Hira/Info.plist $(BUNDLE)/Contents/Info.plist
	@cp Hira/Ressources/lecteur.html $(RES)/
	@cp Hira/Ressources/logo/RadiokoLeka.icns $(RES)/
	@codesign --force --sign - $(BUNDLE)
	@echo "  $(BUNDLE) — $$(du -sh $(BUNDLE) | cut -f1)"

# Session reelle, racontee sur la sortie d erreur. La fenetre s ouvre, joue, et
# se ferme seule : c est ce qui permet de verifier sans regarder l ecran.
lancer: $(BUNDLE)
	@$(MACOS)/$(NOM) --secondes $(or $(S),25)

# Binaire universel. La moitie arm64 est compilee a l aveugle depuis une
# machine Intel : elle n a pas ete executee.
universel: $(SOURCES)
	@mkdir -p build/intel build/arm $(MACOS) $(RES)
	swiftc -O $(CADRES) -target x86_64-apple-macos$(MIN) -o build/intel/$(NOM) $(SOURCES)
	swiftc -O $(CADRES) -target arm64-apple-macos$(MIN)  -o build/arm/$(NOM)   $(SOURCES)
	lipo -create build/intel/$(NOM) build/arm/$(NOM) -output $(MACOS)/$(NOM)
	@cp Hira/Info.plist $(BUNDLE)/Contents/Info.plist
	@cp Hira/Ressources/lecteur.html $(RES)/
	@cp Hira/Ressources/logo/RadiokoLeka.icns $(RES)/
	@codesign --force --sign - $(BUNDLE)
	@lipo -archs $(MACOS)/$(NOM) | sed 's/^/  architectures : /'

# Volontairement laconique : `make propre` efface le dossier build, rien d autre.
propre:
	rm -r build
