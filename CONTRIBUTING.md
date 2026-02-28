# Come contribuire a WinOpt

Grazie per l'interesse. Contributi benvenuti — segui queste linee guida per mantenere il progetto coerente e sicuro.

---

## Prima di aprire una Pull Request

1. **Testa su VM** — non inviare script non testati. Usa una VM Windows 11 pulita.
2. **Un modulo per PR** — non mescolare modifiche a moduli diversi nella stessa PR.
3. **Segui lo stile esistente** — logging con `Write-Log`, backup prima delle modifiche, `Assert-Admin` come safety net.

## Struttura di un modulo

Ogni modulo deve:
- Usare `Write-Log $Log "messaggio" "LEVEL"` per tutti i messaggi (OK/WARN/FAIL/SKIP/INFO)
- Fare backup di registro/servizi/task prima di modificare
- Terminare con `Write-WinOptFooter`
- Avere un commento in testa che descrive cosa fa il modulo

## Cosa accettiamo

- Fix di bug documentati con descrizione del problema
- Nuove chiavi di registro privacy/performance ben documentate
- Aggiornamento pattern debloat o startup per nuove app bloatware
- Miglioramenti al logging o alla gestione errori

## Cosa non accettiamo

- Modifiche che disabilitano Windows Defender o componenti di sicurezza
- Modifiche aggressive a driver o componenti kernel
- Script che scaricano contenuto da internet durante l'esecuzione
- Rimozione dei meccanismi di backup/restore

## Segnalare un bug

Apri una Issue con:
- Versione Windows (build esatta: `winver`)
- Modulo che ha causato il problema
- Contenuto del log in `C:\WinOpt\Logs\`
- Comportamento atteso vs comportamento osservato

## Segnalare un problema di sicurezza

Non aprire una Issue pubblica. Vedi [SECURITY.md](SECURITY.md).
