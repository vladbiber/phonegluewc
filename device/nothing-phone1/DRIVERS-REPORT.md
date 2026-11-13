# Nothing Phone (1) / Nura: raport drivere (2026-11-12)

Kernel 7.2.9 (pmOS edge), slot activ `_a`. Totul de mai jos a fost verificat după un reboot normal pe imaginea scrisă permanent.

## Ce s-a scris pe telefon

| Ce | Unde |
|---|---|
| boot_a nou (DT modificat) | sha256 `a82a5e1b56e460fb4d875a0ad7a3bad3780b71724a7c59641cf944109ddabe90`, sursa `~/nothing-phone1/drivers/bootimg/boot-drivers.img` |
| același DTB în /boot | `/boot/boot.img`, `/boot/dtbs/qcom/sm7325-nothing-spacewar.dtb`, `/boot/sm7325-nothing-spacewar.dtb` |
| module out-of-tree | `/lib/modules/7.2.9/updates/`: `qcom-hv-haptics-lite.ko`, `nvmem-reboot-mode.ko`, `nvmem_qcom-spmi-sdam.ko` |
| s5kjn1 hack scos | mutat în `/var/lib/spacewar-drivers/s5kjn1.ko.override`; acum merge driverul din kernel |
| udev / modprobe | `/etc/udev/rules.d/70-nothing-spacewar-haptics.rules`, `/etc/modules-load.d/nothing-spacewar-haptics.conf`, `/etc/modprobe.d/cfg80211-regdom.conf` (RO) |
| pachete noi | feedbackd, pipewire-spa-bluez, wireplumber-logind, iw, iio-sensor-proxy, modemmanager (ModemManager activat) |

Nicio altă partiție n-a fost atinsă (doar boot_a).

Modificările DT (`~/nothing-phone1/drivers/spacewar-dts.patch`, aplicat în `~/nothing-phone1/kernel/linux-7.2.9-sc7280`):
- `linux,cma` 256 MB (în loc de `cma=256M` pe cmdline);
- s5kjn1: MCLK 24 MHz prin `assigned-clocks`/`assigned-clock-rates`, link 700 MHz;
- nod `pm8350b_haptics: haptics@f000`.

## Rollback

Backup-uri: `~/nothing-phone1/backup-20261112-drivers/` (boot_a/b, dtbo_a/b, SHA256SUMS, slots.txt, `boot-dtb-and-updates.tar`). Backup-ul complet de la 19:34 e în `~/nothing-phone1/backup-20261112-1934/`.

```sh
# din fastboot (telefon: ssh ... 'sudo systemctl reboot --reboot-argument=bootloader', sau Vol- + Power)
fastboot flash boot_a ~/nothing-phone1/backup-20261112-drivers/boot_a.img
fastboot reboot
# apoi pe telefon, ca root:
tar -C / -xf boot-dtb-and-updates.tar          # dtb + updates/ vechi
cp /var/lib/spacewar-drivers/s5kjn1.ko.override /lib/modules/7.2.9/updates/s5kjn1.ko && depmod -a
```
Fără DT-ul nou, s5kjn1 din kernel pornește la 19,2 MHz și camera din spate nu merge; de aceea, la rollback, override-ul trebuie pus înapoi.

**Atenție la update de kernel** (`deviceinfo_flash_kernel_on_update=true`): un `apk upgrade` cu kernel nou rescrie boot-ul cu DTB stock și modulele din `updates/` nu mai corespund. După un astfel de update trebuie reaplicat `spacewar-dts.patch` pe noul DTB și recompilate cele 3 module. Comanda e în Makefile-urile din `~/nothing-phone1/drivers/*/`.

## 1. Vibrații: MERGE

- Am scris driverul `qcom-hv-haptics-lite` (`~/nothing-phone1/drivers/hv-haptics/`): device FF_RUMBLE ff-memless, numit `pm8350b-haptics`, cu auto-rezonanță. Se leagă din nodul DT `haptics@f000`.
- Regula udev îi dă acces sesiunii (uaccess) și îl marchează pentru feedbackd (`FEEDBACKD_TYPE=vibra`).
- Verificat ca user `user` cu `rumble`, și prin `fbcli` (feedbackd).
- Mesajul pentru phone-polish: `phonekbd` trebuie repornit; un click de 18 ms poate fi prea slab.
- Forța: implicit **medie, 2400 mV** (înainte 3600 mV, „destul de tare”), persistent în `/etc/modprobe.d/nothing-spacewar-haptics.conf`.
- Se poate schimba din mers, fără root (grupul plugdev, regula `/etc/udev/rules.d/71-nothing-spacewar-haptics-strength.rules`): `echo 3000 > /sys/module/qcom_hv_haptics_lite/parameters/vmax_mv`. Se aplică la următoarea vibrație. Valori utile: 1500 (slab) până la 3600 (vechiul tare); driverul taie peste 9150.
- **De testat de tine dimineața:** dacă 2400 se simte „mediu” la tastatură și notificări; dacă nu, ajustează valoarea din fișierul modprobe.

## 2. Cameră: MERGE, calitatea nu e verificată la lumină

- s5kjn1 (frontal, 2048x1536 la 24 fps) și camera din spate (8160x6144 la 10 fps, prin softISP) merg cu driverul din kernel, după reboot permanent.
- Hack-ul din `updates/` a dispărut.
- CMA are acum 256 MB (CmaTotal 270336 kB), deci trucul cu bwrap din phonecam care ascunde `/dev/dma_heap` nu mai e necesar. L-am lăsat neatins, ca să nu stric ce merge.
- phonecam are deja selector de rezoluție (12 MP bin / 50 MP full pe spate, 4 MP pe față). Procesarea raw e în `phonecam-develop`: DPC, nivel de negru, AWB grey-world, demosaic, CCM, denoise, curbă de ton, sharpen, stacking de cadre.
- Captura de 50 MP headless durează aproximativ 6 s și dă un JPEG 8158x6142. Testul a fost noaptea, deci imaginea a ieșit neagră: calitatea (AWB, LSC, zgomot) nu poate fi judecată.
- **De testat de tine:** poze ziua, în ambele rezoluții, plus fața.
- Indexurile din `cam -l` s-au schimbat (1 = spate, 2 = față). phonecam folosește căi, deci nu e afectat.

- Camera frontală (imx471): driverul declara Bayer GRBG, dar senzorul e RGGB, de aici previzualizarea mov. Am instalat modulul corectat în `/lib/modules/7.2.9/updates/imx471.ko` (sursa în `~/nothing-phone1/drivers/imx471-bayer/`, codul devine SRGGB10). Se activează la următorul boot. Rollback: `rm` modulul, apoi `depmod -a`. **De verificat de tine:** previzualizarea camerei frontale nu mai e mov. La un update de kernel, modulul trebuie recompilat.

## 3. IMX766 (camera principală): NU, motivul e mai jos

- camss pe sc7280 suportă deja C-PHY (tabela 3ph sm8250 în `camss-csiphy-3ph-1-0.c`), deci partea de PHY nu e blocajul.
- Blocajul: nu există driver mainline pentru IMX766. La Nothing, tabelele de registre (init, moduri) sunt în blob-urile camx din userspace Android, nu în sursele kernel. Un driver înseamnă reverse-engineering din blob-uri sau loguri i2c din Android, ceea ce înseamnă zile de muncă, nu o noapte.
- Datele pentru DT sunt pregătite, din `nothing-src/dt/msm-extra/camera-devicetree/yupik-camera-sensor-qrd.dtsi`:
  - CCI1 master 0, adresă 0x10 (eeprom 0x50, actuator 0x0c);
  - MCLK2 24 MHz, gpio66 MCLK, gpio77 reset;
  - vio L3J 1,8 V, vana L3I 2,9-3,0 V, v_custom1 L5I 1,8-1,9 V, vdig L1I 1,1-1,2 V, AF L7I 2,96 V.
- Nu am scris niciun WIP în kernel.

## 4. Bluetooth: pornit, scanare OK; pair/A2DP de testat de tine

- hci0 e pornit (adresa 02:00:3D:E5:E5:FD, setată de bootmac). Scanarea a găsit 6 dispozitive.
- Pentru A2DP lipseau două lucruri: `pipewire-spa-bluez` și `wireplumber-logind`. Fără al doilea, WirePlumber sărea peste `monitor.bluez.seat-monitoring` și nu apărea niciodată vreun device BT în PipeWire. Le-am instalat pe amândouă.
- Într-un boot, bluetoothd a fost inactiv fără motiv clar; în toate boot-urile de după a fost activ.
- **De testat de tine:** `bluetoothctl` → scan on / pair / connect cu căștile, apoi muzică (trebuie să apară sink-ul bluez în `wpctl status`).

## 5. Restul

| Componentă | Stare |
|---|---|
| Wi-Fi | regdomain era `00`, acum `RO` (persistent prin modprobe.d). Powersave lăsat pornit, ca pe Android. |
| Reboot în bootloader | Merge acum (`systemctl reboot --reboot-argument=bootloader`), prin modulele SDAM și nvmem-reboot-mode. |
| Senzori | Accelerometru și proximitate merg prin iio-sensor-proxy (libssc). Senzor de lumină nu există. phonegluewc-sensor rulează `monitor-sensor --accel`. **De testat de tine:** auto-rotire, proximitate. |
| Suspend | `mem_sleep=deep` disponibil. Nu l-am testat (fără acțiuni de power în afara reboot-urilor). |
| Limită de încărcare | qcom-battmgr nu expune `charge_control_*` pe acest kernel. Nu am făcut nimic. |
| Modem | Detectat prin QMI (qrtr + rmnet_ipa0), ModemManager pornit. Cade la „GW primary session index unknown”, probabil pentru că nu e SIM. **De testat de tine:** cu SIM, `mmcli -L`, apel, SMS. |
| Microfon | MERGE din 2026-11-13, vezi secțiunea 6. |
| NFC | pn553 la 9-0028 stă în `waiting_for_supplier` (pinctrl), iar `NFC_NXP_NCI` nu e compilat în kernel. Nu am făcut. |
| GPS | Nu există `/dev/gnss` și nici driver GNSS compilat. Nu am făcut. |
| Amprentă | Senzorul Goodix e accesat doar din TEE (QSEE trustlet + HAL Android). Kernelul nu are nod qseecom/tee. **Nefezabil** pe mainline în viitorul apropiat. |
| Glyph | Neatins, verificat on/off după flash. |
| Audio | Neatins. Verificat fără sunet: 1050 de controale prin `amixer -D hw:0`, ruta PRI_MI2S_RX MultiMedia1 activă și salvată în asound.state, sink-ul Speaker prezent. `paplay` a deschis stream-ul, dar nu am ascultat. `amixer -c0` arată doar 18 controale din cauza ctl-remap din UCM-ul NP1; se întâmpla la fel și înainte de flash. **De testat de tine:** un sunet scurt, la volum mic. |

## 6. Microfon (2026-11-13): MERGE

Hardware: codec WCD9385 pe SoundWire (TX `sdw:3:0:0217:010d:00:3`, RX `...:4`), reset pe gpio83, alimentări L18B/L17B/BOB, prin macro-urile LPASS rx/tx/va și ADSP (q6afe, port `TX_CODEC_DMA_TX_3`). Trei microfoane analogice, fără DMIC:

| Microfon | Intrare codec | Bias | Rută |
|---|---|---|---|
| jos (principal) | AMIC1 → ADC1 | MIC BIAS1 | SWR_MIC0 |
| sus | AMIC5 → ADC4 (INP5) | MIC BIAS4 | SWR_MIC5 |
| spate | AMIC3 → ADC2 (INP3) | MIC BIAS3 | SWR_MIC1 |
| cască (USB-C analogic) | AMIC2 → ADC2 (INP2) | MIC BIAS2 | netestat, lipsește comutatorul USB-C |

AMIC4 nu e legat la nimic (tăcere). Pozițiile jos/sus/spate sunt deduse din `mixer_paths_yupikqrd.xml` de pe Android (handset = AMIC1 + AMIC5), nu verificate cu urechea.

Ce lipsea: doar nodurile DT. Driverele (wcd938x, wcd938x-sdw, lpass rx/tx/va macro, soundwire-qcom) erau deja module în kernelul 7.2.9, nu s-a compilat nimic.

Ce s-a schimbat:
- DT: `~/nothing-phone1/drivers/spacewar-audio-dts.patch`, aplicat peste `spacewar-dts.patch` (nod `audio-codec` wcd9385, macro-urile rx/tx/va și swr0/swr1 pornite, `dai@120`, `audio-routing`, legăturile MultiMedia2/3 și „WCD Capture”). Placa are acum pcm 0/1/2; captura e pe pcm 2.
- boot_a rescris de pe telefon cu `dd` (telefonul nu era pe USB, deci fără `fastboot boot`): `~/nothing-phone1/drivers/bootimg/boot-audio.img`, sha256 `4f73aeac…19a1`, DTB sha256 `edf7d1d5…6e31`. Același DTB e în `/boot/sm7325-nothing-spacewar.dtb`, `/boot/dtbs/qcom/` și `/boot/boot.img`. S-a schimbat doar DTB-ul (rețeta de împachetare reproduce bit cu bit imaginea veche).
- `/usr/local/bin/np1-mic bottom|top|back|headset` (sursa în `drivers/audio/np1-mic`): pune ruta în mixer; ca root o și salvează în `/var/lib/alsa/asound.state`. Implicit: `bottom`.
- `~/.config/wireplumber/wireplumber.conf.d/53-np1-mic.conf` (sursa în `drivers/audio/`): sursa `alsa_input.platform-sound.pro-input-2` devine „Microphone”, mono; nodurile pro-audio fără rută sunt dezactivate. Profilul rămâne pro-audio, ca la difuzor.

Capcane găsite:
- ADSP-ul nu livrează niciun eșantion dacă primul decimator activ nu e DEC0 (cu DEC1 singur, citirea dă I/O error). UCM-ul NP1 din pachet folosește DEC1, deci rutele lui de microfon nu merg.
- Profilul HiFi din UCM tot nu se încarcă: cere și legătura de căști (`RX_CODEC_DMA_RX_0`), pe care nu am pus-o în DT.
- `TX0 MODE = ADC_HIFI` dă zgomot de bandă largă la -8 dBFS; se folosește `ADC_NORMAL`.
- Schimbarea rutei cu captura deschisă dă tăcere digitală; `np1-mic` așteaptă să se închidă PCM-ul.
- `pactl suspend-source` pe sursa pro-audio lasă și difuzorul blocat (snd_pcm_start: Broken pipe) până la repornirea PipeWire.
- La fiecare deschidere apare `soundwire sdw-master-2-0: clock stop deprepare wait failed:-110` și circa 0,6 s întârziere (magistrala RX, pe care stă și haptics-ul SoundWire nefolosit). Inofensiv.
- Volumul salvat de WirePlumber pentru aplicația `paplay` e -80 dB (rămas de la un test mai vechi): un `paplay` simplu pare mut.

Verificat după un reboot normal: modulele se încarcă singure, ruta revine din `asound.state`, sursa „Microphone” și sink-ul „Speaker” apar, `parecord` prinde tonul de test. Tot după reboot: ecran și shell pornite, touch prezent, Wi-Fi, difuzor (ton auzit de microfon), vibrații (auzite de microfon), camera din spate.

Cameră: clipul făcut cu phonecam are acum pistă audio (h264 1080p + AAC mono 44,1 kHz, verificat cu ffprobe, tonul de test e în pistă). Codul camerei nu a fost schimbat. Mostre: `~/nothing-phone1/mic-samples/` (`camera-clip-with-sound.mp4`, `mic-bottom.wav`, `mic-top.wav`, `mic-back.wav`, `after-reboot-bottom-mic.wav`); conțin doar zgomotul camerei și un ton de 1 kHz din difuzor, nu voce.

Niveluri (ADC 12 = +18 dB analogic, ca pe Android; TX_DEC0 96 = +12 dB digital): zgomot de fond între -69 și -76 dBFS RMS (cameră, nu neapărat liniștită), brum 50-150 Hz sub -85 dBFS, tonul de test (difuzor la 75%) la -38 dBFS RMS pe jos, -33 pe spate, -29 pe sus, fără clipping. În prima secundă după deschidere nivelul de joasă frecvență e mai mare (așezarea bias-ului). Câștigul e ales din calcul (sensibilitate tipică MEMS), nu din voce reală.

Rollback: `~/nothing-phone1/backup-20261113-audio/boot_a.img` (sha256 `da353ca1…e70c`, = boot_a dinainte, cu DT-ul de haptics/cameră/CMA). Există și pe telefon: `sudo dd if=/home/user/boot_a-rollback.img of=/dev/disk/by-partlabel/boot_a bs=4M conv=fsync`, sau `fastboot flash boot_a` cu același fișier. După rollback trebuie pus înapoi și DTB-ul vechi în `/boot` (e în `boot-dtb-and-updates.tar`).

**După un update de kernel:** se aplică pe noul DTS `spacewar-dts.patch` și apoi `spacewar-audio-dts.patch`, se pune DTB-ul în `/boot` și în boot_a. Modulele audio vin cu kernelul, nu trebuie recompilate. `np1-mic`, `asound.state` și fișierul WirePlumber rămân. Dacă noul kernel are deja nodurile wcd în DT (ramura sc7280-7.3.y le are), patch-ul audio nu mai e necesar, dar `audio-routing` de acolo leagă AMIC3/AMIC4 altfel și nu are AMIC5: de verificat microfonul de sus.

## Surse

- `~/nothing-phone1/drivers/hv-haptics/`: driver + regulă udev.
- `~/nothing-phone1/drivers/nvmem-reboot-mode/`: modulele SDAM și reboot-mode.
- `~/nothing-phone1/drivers/spacewar-dts.patch` și `sm7325-nothing-spacewar.dts.orig`.
- `~/nothing-phone1/drivers/bootimg/boot-drivers.img`. Reconstruit pe telefon cu mkbootimg-osm0sis, header v2, dtb_offset 0x01f00000. ABL-ul citește secțiunea dtb a imaginii, nu DTB-ul lipit la kernel.
