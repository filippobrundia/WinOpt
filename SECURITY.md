# Security Policy

## Versioni supportate

| Versione | Supportata |
|---|---|
| 2.5.7 | ✅ Sì |
| < 2.5.7 | ❌ No |

## Segnalare una vulnerabilità

**Non aprire una Issue pubblica per problemi di sicurezza.**

Se trovi una vulnerabilità (es. script che può essere usato per privilege escalation non intenzionale, bypass di meccanismi di sicurezza Windows, o comportamento pericoloso non documentato):

1. Apri una **GitHub Security Advisory** privata nel repository
   (tab Security → Advisories → New draft security advisory)
2. Descrivi il problema, la versione interessata e i passi per riprodurlo
3. Riceverai risposta entro 7 giorni

## Cosa consideriamo una vulnerabilità

- Comportamenti che permettono esecuzione di codice arbitrario non intenzionale
- Script che scaricano ed eseguono contenuto remoto non verificato
- Meccanismi di backup/restore che sovrascrivono file di sistema in modo non sicuro

## Cosa NON è una vulnerabilità

- Il fatto che la suite disabilita servizi Windows (è il suo scopo dichiarato)
- Compatibilità con versioni Windows non supportate
- Comportamento diverso da quanto documentato su configurazioni non standard
