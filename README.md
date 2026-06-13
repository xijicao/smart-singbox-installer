# Smart sing-box 绠€鍖栫増

杩欐槸缁?DMIT / HK / 瀹跺钀藉湴浣跨敤鐨勭畝鍖栫増瀹夎鍣ㄣ€?
## 鍏堟敼 DMIT/HK 鐨?SSH 绔彛

DMIT 鍜?HK 鍏ュ彛鏈轰細鍚敤闃茬伀澧欙紝鍙斁琛岋細

```text
TCP 443    sing-box Reality
TCP 浣犵殑 SSH 楂樹綅绔彛
```

鎵€浠ュ湪 DMIT/HK 涓婅繍琛屽畨瑁呰剼鏈墠锛屽厛鎶?Debian/Ubuntu 鐨?SSH 绔彛鏀规垚涓€涓綘鑷繁閫夌殑楂樹綅绔彛锛屼緥濡?`51398`銆乣38471`銆乣45678`銆備笉瑕佹妸浣犵殑鐪熷疄绔彛鍐欏埌鍏紑浠撳簱閲屻€?
缂栬緫 SSH 閰嶇疆锛?
```sh
nano /etc/ssh/sshd_config
```

鎵惧埌杩欎竴琛岋細

```text
#Port 22
```

鏀规垚浣犺嚜宸遍€夌殑楂樹綅绔彛锛屼緥濡傦細

```text
Port 51398
```

淇濆瓨骞堕€€鍑?nano锛?
```text
Ctrl + O
Enter
Ctrl + X
```

閲嶅惎 SSH锛?
```sh
systemctl restart ssh
```

鏈変簺绯荤粺鏈嶅姟鍚嶆槸 `sshd`锛屽鏋滀笂闈㈠け璐ワ紝灏辨墽琛岋細

```sh
systemctl restart sshd
```

鐒跺悗鍏堜笉瑕佸叧闂綋鍓?SSH 绐楀彛锛屾柊寮€涓€涓獥鍙ｆ祴璇曪細

```sh
ssh -p 51398 root@浣犵殑鏈嶅姟鍣↖P
```

鎶婁笂闈㈢殑 `51398` 鎹㈡垚浣犲疄闄呰缃殑 SSH 绔彛銆傜‘璁ゆ柊绔彛鍙互鐧诲綍鍚庯紝鍐嶈繍琛屾湰瀹夎鑴氭湰銆傚畨瑁?DMIT/HK 鏃惰剼鏈細璇㈤棶锛?
```text
SSH port to allow in firewall
```

杩欓噷蹇呴』濉啓浣犲疄闄呰缃殑 SSH 绔彛銆傝繖涓楠ゅ緢閲嶈锛屽惁鍒欓槻鐏鍚敤鍚庡彲鑳借繘涓嶅幓鏈哄櫒銆?
璁捐鐩爣锛?
- DMIT 鍜?HK 鍙仛鍏ュ彛锛岀洃鍚?`443`锛孯eality 鍏ョ珯銆?- 瀹跺鍙仛 SS2022 钀藉湴锛岀敓鎴?`ss://` 閾炬帴銆?- 鍦?DMIT/HK 涓婄矘璐村瀹界殑 `ss://`锛岃嚜鍔ㄧ敓鎴愪竴涓柊鐨?Reality 涓浆閾炬帴銆?- 鍚庣画鍙互娣诲姞鏈嬪弸鐩磋繛鐢ㄦ埛锛屼篃鍙互鍒犻櫎鏈嬪弸鎴栨煇涓瀹借惤鍦般€?- sing-box 浣跨敤 systemd/OpenRC 鎵樼锛屾満鍣ㄩ噸鍚悗鑷姩鎷夎捣銆?- DMIT/HK 鐨?nftables 闃茬伀澧欏彧鏀捐鍏ョ珯 TCP `443` 鍜屼綘瀹夎鏃跺～鍐欑殑 SSH 绔彛銆?- 瀹跺 SS2022 涓嶈姹備娇鐢?`443`锛屽叕缃戞槧灏勭鍙ｅ彲浠ユ槸闈㈡澘缁欎綘鐨勪换鎰?TCP 绔彛銆?- DMIT/HK 鐨?direct 鍑虹珯宸茶缃负 `prefer_ipv4`銆侱MIT 鍙屾爤鏃朵細浼樺厛 IPv4 鍑虹珯锛汬K 濡傛灉鏈潵鍙湁 IPv4锛屼笉闇€瑕侀澶栧鐞嗐€?
## 涓€閿畨瑁?
濡傛灉鏂版満鍣ㄦ彁绀?`curl: command not found`锛屽厛瀹夎 curl锛?
Debian/Ubuntu锛?
```sh
apt-get update && apt-get install -y curl ca-certificates
```

Alpine锛?
```sh
apk update
apk add --no-cache curl ca-certificates iproute2 netcat-openbsd
```

涓婁紶鍒?GitHub 鍚庝娇鐢細

```sh
curl -fsSL https://raw.githubusercontent.com/xijicao/smart-singbox-installer/main/install.sh | sh
```

濡傛灉浣犲厛鍦ㄦ湰鍦版祴璇曪紝涔熷彲浠ョ洿鎺ワ細

```sh
sh install.sh
```

## 鑿滃崟

```text
1. DMIT Debian entry / DMIT 涓诲姏鍏ュ彛
2. HK Debian entry / HK 鍥介檯浜掕繛鍏ュ彛
3. Home landing / 瀹跺钀藉湴鎴栫洿杩?4. Add ss:// to this entry / 缁欏綋鍓嶅叆鍙ｆ坊鍔犺惤鍦?0. Exit
```

DMIT/HK 鍙敮鎸?Debian/Ubuntu銆傚瀹芥敮鎸?Debian/Ubuntu/Alpine銆?
## 瀹跺鏈哄櫒

鍦ㄥ瀹芥満鍣ㄤ笂閫夋嫨 `3`锛岃剼鏈細鐢熸垚锛?
```text
/root/singbox-home-info.txt
```

閲岄潰鏈夛細

```text
ss_link:
ss://...

ss_link_editable:
ss://method:password@server:port#name
```

瀹夎鏃朵細鍏堥€夋嫨妯″紡锛?
```text
1. SS2022 landing only
2. Reality direct only
3. SS2022 landing + Reality direct
```

鎬庝箞閫夛細

- 瀹跺鐩磋繛璐ㄩ噺涓€鑸紝鍙兂缁?DMIT/HK 褰撹惤鍦帮細閫?`1`
- 瀹跺鐩磋繛璐ㄩ噺寰堝ソ锛屾兂瀹㈡埛绔洿鎺ヨ繛瀹跺锛氶€?`2`
- 鏃㈡兂缁?DMIT/HK 褰撹惤鍦帮紝鍙堟兂淇濈暀鐩磋繛鍏ュ彛锛氶€?`3`

### SS2022 绔彛

濡傛灉鍚敤 SS2022锛屼細闂袱涓鍙ｏ細

```text
SS internal listen port
SS public mapped port
```

鏅€氱嫭绔嬪叕缃?VPS 鍙互涓や釜閮藉～ `443`锛屾垨鑰呴兘濉綘鎯崇敤鐨勭鍙ｃ€?
NAT/LXC/瀹跺闈㈡澘鏈哄櫒瑕佸垎寮€濉€備緥濡傞潰鏉挎槧灏勬槸锛?
```text
鍏綉 TCP 24496 -> 瀹瑰櫒 TCP 443
```

閭ｄ箞濉啓锛?
```text
SS internal listen port: 443
SS public mapped port: 24496
```

鐢熸垚鐨?`ss_link` 浼氳嚜鍔ㄤ娇鐢ㄥ叕缃戠鍙?`24496`锛孌MIT/HK 瀵煎叆鏃跺氨鑳借繛瀵广€?
### Reality 绔彛

濡傛灉鍚敤 Reality锛屼細闂袱涓鍙ｏ細

```text
Reality internal listen port
Reality public mapped port
```

绔彛寤鸿锛?
- Reality only锛氫紭鍏堢敤 `443`
- SS2022 + Reality 鍚屾椂瀹夎锛氬缓璁?SS2022 鐢?`443`锛孯eality 鐢?`8443`
- NAT/LXC 闈㈡澘鏈哄櫒锛氬唴閮ㄧ鍙ｅ～瀹瑰櫒閲岀洃鍚殑绔彛锛屽叕缃戠鍙ｅ～闈㈡澘鏄犲皠缁欎綘鐨勭鍙?- 瀹跺 Reality 閰嶇疆浣跨敤鏈€灏忓吋瀹规ā鏉匡紝涓嶅惎鐢?`tcp_fast_open`锛屼篃涓嶉檺鍒?`max_time_difference`锛屽敖閲忚创杩戝凡楠岃瘉鍙敤鐨勪竴閿剼鏈厤缃€?
涓句緥锛?
```text
鍏綉 TCP 24497 -> 瀹瑰櫒 TCP 8443
```

閭ｄ箞濉啓锛?
```text
Reality internal listen port: 8443
Reality public mapped port: 24497
```

Reality 鐨?SNI 榛樿鏄棩鏈柟鍚戠殑 `www.sony.jp`銆傚畨瑁呮椂浼氶棶 `Reality SNI`锛屽彲浠ユ寜瀹跺鍦板尯鎵嬪姩濉細

```text
JP / 鏃ユ湰锛歸ww.sony.jp
HK / 棣欐腐锛歸ww.hkex.com.hk
TW / 鍙版咕锛歸ww.cht.com.tw
```

濡傛灉浣犵煡閬撴煇涓湴鍖烘洿鍚堥€傜殑鎻℃墜鍩熷悕锛屼篃鍙互瀹夎鏃舵墜鍔ㄨ緭鍏ャ€傝繖閲屽～鐨勬槸浼鎻℃墜鍩熷悕锛屼笉鏄綘鐨勬湇鍔″櫒鍩熷悕銆?
## DMIT/HK 娣诲姞瀹跺钀藉湴

鍦?DMIT 鎴?HK 涓婃墽琛岋細

```sh
sb add-ss 'ss://...'
```

鎴栬€呯洿鎺ヨ繍琛岋細

```sh
sb
```

閫夋嫨 `Add SS landing`锛岀矘璐村瀹介摼鎺ャ€傝剼鏈細鑷姩锛?
- 鏂板涓€涓?`relay-*` Reality 鐢ㄦ埛
- 鏂板涓€涓搴旂殑 Shadowsocks outbound
- 鏂板涓€鏉℃寜鐢ㄦ埛鍒嗘祦鐨?route rule
- 妫€鏌ラ厤缃?- 閲嶅惎 sing-box
- 杈撳嚭鏂扮殑 `vless://` Reality 涓浆閾炬帴

## DMIT/HK 绠＄悊鍛戒护

```sh
sb
sb links
sb test
sb backup
sb restore-latest
sb list-relays
sb add-ss 'ss://...'
sb del-relay relay-jp-home-SS
sb add-friend fr1
sb del-user fr1
sb restart
sb uninstall
sb purge
```

璇存槑锛?
- `add-friend` 娣诲姞鐨勬槸鐩磋繛 Reality 鐢ㄦ埛锛岄粯璁よ蛋 direct銆?- `add-ss` 娣诲姞鐨勬槸钀藉湴涓浆鐢ㄦ埛锛屽悕瀛椾細浠?`relay-` 寮€澶淬€?- 鍒犻櫎钀藉湴璇风敤 `del-relay`锛屽垹闄ゆ湅鍙嬬敤 `del-user`銆?- 瀹跺 SS2022 鐨勭鍙ｄ笉闇€瑕佹槸 `443`銆侱MIT/HK 杩炴帴瀹跺灞炰簬鍑虹珯娴侀噺锛屽叆鍙ｆ満闃茬伀澧欎笉浼氶檺鍒惰繖涓嚭绔欑鍙ｃ€?- `test` 浼氭鏌?sing-box 鐗堟湰銆侀厤缃€佹湇鍔＄姸鎬佸拰鐩戝惉绔彛銆?- `backup` 浼氭妸褰撳墠閰嶇疆澶囦唤鍒?`/etc/sing-box/backups`銆?- `restore-latest` 浼氭仮澶嶆渶鏂伴厤缃浠斤紝鎭㈠鍓嶄細鍏堝浠藉綋鍓嶇姸鎬併€?- `uninstall` 浼氬厛鎵撳寘澶囦唤鍒?`/root/singbox-entry-uninstall-backup-*.tar.gz`锛屽啀鍋滄 sing-box 骞跺垹闄ゅ叆鍙ｉ厤缃拰 `sb` 绠＄悊鍣ㄣ€?- `purge` 鏄棤澶囦唤寮哄埗娓呯悊锛屼細鍋滄 sing-box銆佸垹闄?`/etc/sing-box`銆佸垹闄?`sb` 鍜屼俊鎭枃浠躲€侱MIT/HK 涓嶄細鑷姩鍏抽棴 nftables锛岄伩鍏嶆剰澶栨毚闇?SSH銆?
濡傛灉鎯充氦浜掑紡鍒犻櫎钀藉湴锛岀洿鎺ヨ繍琛岋細

```sh
sb
```

閫夋嫨 `Delete relay` 鍚庝細鍒楀嚭缂栧彿锛屼笉闇€瑕佹墜鎵撳畬鏁?`relay-*` 鍚嶅瓧銆?
## 瀹跺绠＄悊鍛戒护

瀹跺鏈哄櫒瀹夎鍚庝篃鏈?`sb`锛?
```sh
sb
sb info
sb test
sb status
sb restart
sb reset-ss
sb uninstall
sb purge
```

璇存槑锛?
- `info` 鏌ョ湅褰撳墠 SS 閾炬帴銆?- 濡傛灉瀹夎浜?Reality锛宍info` 涔熶細鏄剧ず `vless://` 鐩磋繛閾炬帴銆?- `test` 妫€鏌?sing-box 鐗堟湰銆侀厤缃€佹湇鍔＄姸鎬佸拰鐩戝惉绔彛銆?- `reset-ss` 浼氶噸鏂扮敓鎴?SS2022 瀵嗙爜锛屾洿鏂?`/etc/sing-box/config.json`锛岄噸鍚湇鍔★紝骞跺埛鏂?`/root/singbox-home-info.txt`銆?- Reality only 妯″紡娌℃湁 SS2022锛屼笉鑳戒娇鐢?`reset-ss`銆?- `uninstall` 浼氬厛鎵撳寘澶囦唤鍒?`/root/singbox-home-uninstall-backup-*.tar.gz`锛屽啀鍒犻櫎瀹跺钀藉湴瀹夎銆?- `purge` 鏄棤澶囦唤寮哄埗娓呯悊锛屼細鍋滄 sing-box锛屽垹闄?`/etc/sing-box`銆乣/root/singbox-home-info.txt` 鍜?`sb`銆?
濡傛灉 `sb` 宸茬粡鍧忎簡鎴栦笉瀛樺湪锛屼篃鍙互閲嶆柊杩愯瀹夎鑴氭湰锛岄€夋嫨锛?
```text
5. Purge current install without backup
```

杩欎釜閫夐」涓嶄緷璧栨棫鐨?`sb`锛岄€傚悎鍙嶅娴嬭瘯鏃舵竻绌虹幆澧冨悗閲嶈銆?
## 鏃ュ父缁存姢鍜屾鏌?
### 鏈嶅姟鎬ц兘璁剧疆

Debian/Ubuntu 鏈哄櫒浼氬啓鍏?`/etc/systemd/system/sing-box.service`锛屾牳蹇冭缃槸锛?
```ini
User=root
WorkingDirectory=/etc/sing-box
ExecStartPre=/usr/local/bin/sing-box check -c /etc/sing-box/config.json
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
```

璇存槑锛?
- `ExecStartPre`锛氬惎鍔ㄥ墠鍏堟鏌ラ厤缃紝鎵嬫敼閰嶇疆鍑洪敊鏃朵笉浼氬甫鐥呭惎鍔ㄣ€?- `Restart=on-failure` / `RestartSec=3`锛氬紓甯搁€€鍑哄悗 3 绉掕嚜鍔ㄦ媺璧凤紱鎵嬪姩鍋滄鏈嶅姟鏃朵笉浼氬弽澶嶅娲汇€?- `LimitNOFILE=1048576`锛氭彁楂樻枃浠舵弿杩扮涓婇檺锛岄€傚悎 DMIT 2G 甯﹀杩欑鍏ュ彛鏈恒€?- 涓嶈缃?`OOMScoreAdjust=-1000`锛?G 鍐呭瓨鏈哄櫒鏇寸ǔ濡ワ紝閬垮厤绯荤粺鍐呭瓨绱у紶鏃?SSH 鎴栧叾瀹冪郴缁熻繘绋嬫洿瀹规槗鍏堣鏉€銆?
杩欏 service 浼氱敤浜?DMIT/HK 鍏ュ彛鏈猴紝涔熶細鐢ㄤ簬 Debian/Ubuntu 瀹跺鏈恒€侫lpine 瀹跺鏈轰娇鐢?OpenRC锛屽苟寮€鍚?`respawn` 鑷姩鎷夎捣銆?
浣犵殑鏈哄櫒瑙勬牸涓嬪缓璁細

- DMIT锛?G 甯﹀銆?C1G锛岄€傚悎浣滀富鍔涘叆鍙ｏ紝淇濈暀杩欏楂樿繛鎺ヤ笂闄愰厤缃€?- HK锛?0Mbps銆?C1G锛屼笉闄愭祦閲忥紝鐡堕鏄甫瀹斤紝涓嶆槸 CPU锛屼繚鐣欏悓鏍烽厤缃篃娌￠棶棰樸€?- 瀹跺/LXC锛氶噸鐐规槸绔彛鏄犲皠绋冲畾鍜屾湇鍔¤嚜鍔ㄦ媺璧凤紝OpenRC/systemd 閮藉凡閰嶇疆鑷姩閲嶅惎銆?
### 閫氱敤鍛戒护

DMIT銆丠K銆佸瀹芥満鍣ㄩ兘鍙互鍏堢敤 `sb test` 鍋氫竴娆℃€绘鏌ャ€傝繖涓懡浠ら€傚悎鍦ㄨ繖浜涙儏鍐典娇鐢細

- 鍒氬畨瑁呭畬鎴愶紝鎯崇‘璁?sing-box 鏄惁姝ｅ父銆?- 閲嶅惎鏈哄櫒鍚庯紝鎯崇‘璁ゆ湇鍔℃槸鍚﹁嚜鍔ㄦ媺璧枫€?- 鑺傜偣绐佺劧涓嶈兘鐢ㄤ簡锛屽厛鐪嬫槸涓嶆槸鏈嶅姟鎴栫鍙ｉ棶棰樸€?- 淇敼閰嶇疆銆佹坊鍔犺惤鍦般€侀噸缃瘑鐮佷箣鍚庯紝鎯冲揩閫熺‘璁ゆ湁娌℃湁鍐欏潖閰嶇疆銆?
```sh
sb test
```

瀹冧細渚濇妫€鏌ワ細

```text
sing-box version                         鏌ョ湅 sing-box 鐗堟湰
sing-box check -c /etc/sing-box/config.json  妫€鏌ラ厤缃枃浠舵湁娌℃湁璇硶閿欒
systemd/OpenRC 鏈嶅姟鐘舵€?                  鏌ョ湅鏈嶅姟鏄笉鏄?running
鐩戝惉绔彛                                  鏌ョ湅 sing-box 鏈夋病鏈夌洃鍚搴旂鍙?```

閲嶅惎 sing-box銆傞€傚悎鍦ㄤ慨鏀归厤缃€佺鍙ｃ€佸瘑鐮佸悗浣跨敤锛?
```sh
sb restart
```

鏌ョ湅鏈嶅姟鐘舵€併€傞€傚悎纭 sing-box 鏄惁姝ｅ湪杩愯锛?
```sh
sb status
```

濡傛灉鏌愬彴鏈哄櫒鐨?`sb status` 涓嶅彲鐢紝鍙互鐩存帴鐢ㄧ郴缁熷懡浠ゃ€?
Debian/Ubuntu锛?
```sh
systemctl status sing-box --no-pager
systemctl restart sing-box
journalctl -u sing-box -n 80 --no-pager
```

璇存槑锛?
- `systemctl status sing-box --no-pager`锛氭煡鐪?sing-box 鏈嶅姟鐘舵€併€?- `systemctl restart sing-box`锛氶噸鍚?sing-box銆?- `journalctl -u sing-box -n 80 --no-pager`锛氭煡鐪嬫渶杩?80 琛屾棩蹇楋紝鎺掓煡鍚姩澶辫触銆侀厤缃敊璇€佺鍙ｅ崰鐢ㄧ瓑闂銆?
Alpine锛?
```sh
rc-service sing-box status
rc-service sing-box restart
tail -n 80 /var/log/messages
```

璇存槑锛?
- `rc-service sing-box status`锛氭煡鐪?Alpine/OpenRC 涓嬬殑鏈嶅姟鐘舵€併€?- `rc-service sing-box restart`锛氶噸鍚?sing-box銆?- `tail -n 80 /var/log/messages`锛氭煡鐪嬫渶杩戠郴缁熸棩蹇楋紝鎺掓煡 sing-box 鍚姩闂銆?
鎵嬪姩妫€鏌ラ厤缃枃浠躲€傚彧瑕佷綘鎬€鐤戦厤缃啓鍧忎簡锛屽厛璺戣繖涓細

```sh
sing-box check -c /etc/sing-box/config.json
```

濡傛灉杈撳嚭 `configuration file parsed successfully` 鎴栫被浼兼垚鍔熸彁绀猴紝璇存槑閰嶇疆璇硶娌￠棶棰樸€?
鏌ョ湅鐩戝惉绔彛銆傜敤鏉ョ‘璁?sing-box 鏄惁鐪熺殑鐩戝惉浜嗕綘璁剧疆鐨勭鍙ｏ細

```sh
ss -lntp | grep sing-box
```

濡傛灉绯荤粺娌℃湁 `ss`锛屽彲浠ョ敤锛?
```sh
netstat -lntp | grep sing-box
```

姝ｅ父鎯呭喌涓嬶細

- DMIT/HK 搴旇鐪嬪埌 `:443`銆?- 瀹跺 SS2022 搴旇鐪嬪埌浣犲～鍐欑殑 `SS internal listen port`銆?- 瀹跺 Reality 搴旇鐪嬪埌浣犲～鍐欑殑 `Reality internal listen port`銆?
### LXC/瀹跺绔彛鎺掓煡

瀹跺鏄?LXC 鎴?NAT 闈㈡澘鏃讹紝瀹夎鑴氭湰浼氶棶锛?
```text
SS internal listen port
SS public mapped port
Reality internal listen port
Reality public mapped port
```

鍐呴儴鐩戝惉绔彛鏄鍣ㄩ噷 sing-box 鐪熸鐩戝惉鐨勭鍙ｏ紱鍏綉鏄犲皠绔彛鏄潰鏉垮垎閰嶇粰澶栭潰杩炴帴鐨勭鍙ｃ€?
濡傛灉鏌愪簺绔彛鏈夐棶棰橈紝浼樺厛鎹⑩€滃叕缃戞槧灏勭鍙ｂ€濓紝姣斿锛?
```text
鍏綉 TCP 24496 -> LXC TCP 443
鍏綉 TCP 24497 -> LXC TCP 8443
```

瀹夎鏃跺氨濉細

```text
SS internal listen port: 443
SS public mapped port: 24496

Reality internal listen port: 8443
Reality public mapped port: 24497
```

妫€鏌?LXC 鍐呴儴鏄惁鐩戝惉鎴愬姛銆傝繖涓懡浠ゆ槸鍦ㄥ瀹?LXC 閲岄潰杩愯鐨勶細

```sh
ss -lntp | grep -E ':443|:8443'
```

濡傛灉杩欓噷娌℃湁杈撳嚭锛岃鏄?sing-box 娌℃湁鐩戝惉瀵瑰簲鍐呴儴绔彛锛屽厛鎵ц锛?
```sh
sb test
sing-box check -c /etc/sing-box/config.json
```

浠?DMIT/HK 娴嬭瘯鑳藉惁杩炲埌瀹跺鍏綉绔彛銆傝繖涓懡浠ゆ槸鍦?DMIT 鎴?HK 涓婅繍琛岀殑锛?
```sh
nc -vz 瀹跺鍏綉IP鎴栧煙鍚?24496
nc -vz 瀹跺鍏綉IP鎴栧煙鍚?24497
```

姝ｅ父鎯呭喌浼氱湅鍒扮被浼?`succeeded` 鐨勬彁绀恒€傚鏋滆繛鎺ュけ璐ワ紝浼樺厛妫€鏌ワ細

- 闈㈡澘鍏綉绔彛鏄惁濉敊銆?- 闈㈡澘鏄犲皠鏄惁鐢熸晥銆?- 瀹跺 LXC 鍐呴儴绔彛鏄惁鐩戝惉銆?- 瀹跺杩愯惀鍟嗘垨闈㈡澘鏄惁灞忚斀浜嗚绔彛銆?- `ss://` 鎴?`vless://` 閾炬帴閲岀敤鐨勬槸涓嶆槸鍏綉鏄犲皠绔彛锛岃€屼笉鏄鍣ㄥ唴閮ㄧ鍙ｃ€?
濡傛灉娌℃湁 `nc`锛孌ebian/Ubuntu 鍙互瀹夎锛?
```sh
apt-get update && apt-get install -y netcat-openbsd
```

Alpine 鍙互瀹夎锛?
```sh
apk add --no-cache iproute2 netcat-openbsd
```

`iproute2` 鎻愪緵 `ss` 鍛戒护锛宍netcat-openbsd` 鎻愪緵 `nc` 鍛戒护銆?
## 闃茬伀澧欐彁閱?
DMIT/HK 浼氬啓鍏?nftables锛屽彧鍏佽锛?
```text
鍏ョ珯 TCP 443
鍏ョ珯 TCP 浣犲～鍐欑殑 SSH 绔彛
宸插缓绔嬭繛鎺?loopback
ICMP / IPv6 ICMP
```

杩欐剰鍛崇潃鏅€?SSH `22` 绔彛浼氳鎸℃帀銆傝剼鏈細鍦ㄥ惎鐢ㄩ槻鐏鍓嶈姹傝緭鍏ワ細

```text
ENTRYFW
```

濡傛灉浣犵‘瀹氳嚜宸卞凡缁忔敼濂?SSH 绔彛锛屾垨鑰呮湁鎺у埗鍙般€佹晳鎻存ā寮忥紝涔熷彲浠ョ敤锛?
```sh
FORCE_ENTRY_FIREWALL=1 sh install.sh
```

## 鐢熸垚鏂囦欢

鍏ュ彛鏈猴細

```text
/etc/sing-box/config.json
/etc/sing-box/entry.env
/root/singbox-entry-info.txt
/usr/local/bin/sb
```

瀹跺鏈猴細

```text
/etc/sing-box/config.json
/etc/sing-box/home.env
/root/singbox-home-info.txt
/usr/local/bin/sb
```

## 鎴戜繚鐣欏拰鑸嶅純鐨勯儴鍒?
淇濈暀锛?
- DMIT/HK 鐨?Reality 鍏ュ彛璁捐
- `ss://` 瀵煎叆鍚庤嚜鍔ㄧ敓鎴?Reality 涓浆鑺傜偣
- 鏈嬪弸鐢ㄦ埛娣诲姞/鍒犻櫎
- 閲嶅惎鑷媺璧?- 閰嶇疆妫€鏌ュけ璐ヨ嚜鍔ㄥ洖婊?- 443 + 鑷畾涔?SSH 绔彛鍏ュ彛闃茬伀澧?
鑸嶅純锛?
- 澶?profile 澶嶆潅鍒嗗弶
- 杩囧 README 鍜屾灦鏋勫浘
- 瀹跺 Reality + SS 娣峰悎妯″紡
- 涓嶅父鐢ㄧ殑澶囦唤鎭㈠鑿滃崟
- 澶嶆潅鐨勫叏鑷姩绔彛鐚滄祴
