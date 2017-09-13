# DUMLrub
Ruby port of PyDUML 

Main executables:
```
BackDatAssUp.rb - This mimics the "backup" button inside DUMLdore, with a bit more rigorous checks on structure. 
CherryPicker.rb - Tool to "reroll" firmware binaries with specific modules selected. 
LogJammer.rb - Standalone tool for reading upgrade00.log
RubaDubDUML.rb - analog of pyduml.py, used for pushing firmware binaries over serial via DUML protocol 
```
Git Submodule repos:
```
exploits - folder contains public and private exploits such as RedHerring converted to use RubaDubDUML as a library
firm_cache - individual firmware modules from DJI firmware 
bins - dji_system.bin stash
```

Awwwww it feels soooooo good. 

Rub-a-dub-dub,
Three men in a tub,
And who do you think they be?

The butcher, the baker, the candlestick maker,
Turn them out, knaves all three

https://en.wikipedia.org/wiki/Rub-a-dub-dub

![feels good](https://media1.giphy.com/media/iCOrqDgajehbi/giphy.gif)

### #DeejayeyeHackingClub information repos aka "The OG's" (Original Gangsters)

http://dji.retroroms.info/ - "Wiki"

https://github.com/fvantienen/dji_rev - This repository contains tools for reverse engineering DJI product firmware images.

https://github.com/Bin4ry/deejayeye-modder - APK "tweaks" for settings & "mods" for additional / altered functionality

https://github.com/hdnes/pyduml - Assistant-less firmware pushes and DUMLHacks referred to as DUMBHerring when used with "fireworks.tar" from RedHerring. DJI silently changes Assistant? great... we will just stop using it.

https://github.com/MAVProxyUser/P0VsRedHerring - RedHerring, aka "July 4th Independence Day exploit", "FTPD directory transversal 0day", etc. (Requires Assistant). We all needed a public root exploit... why not burn some 0day?

https://github.com/MAVProxyUser/dji_system.bin - Current Archive of dji_system.bin files that compose firmware updates referenced by MD5 sum. These can be used to upgrade and downgrade, and root your I2, P4, Mavic, Spark, Goggles, and Mavic RC to your hearts content. (Use with pyduml or DUMLDore)

https://github.com/MAVProxyUser/firm_cache - Extracted contents of dji_system.bin, in the future will be used to mix and match pieces of firmware for custom upgrade files. This repo was previously private... it is now open.

https://github.com/MAVProxyUser/DUMLrub - Ruby port of PyDUML, and firmware cherry picking tool. Allows rolling of custom firmware images.

https://github.com/jezzab/DUMLdore - Even windows users need some love, so DUMLDore was created to help archive, and flash dji_system.bin files on windows platforms.

https://github.com/MAVProxyUser/DJI_ftpd_aes_unscramble - DJI has modified the GPL Busybox ftpd on Mavic, Spark, & Inspire 2 to include AES scrambling of downloaded files... this tool will reverse the scrambling

https://github.com/darksimpson/jdjitools - Java DJI Tools, a collection of various tools/snippets tied in one CLI shell-like application.
