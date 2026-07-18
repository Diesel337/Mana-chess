# Mana Chess Online - Game Design

## Fantasia

Mana Chess Online es una variante tactica de ajedrez en tiempo real. La promesa corta es: ajedrez con presion en tiempo real, economia de elixir y decisiones tacticas rapidas.

## Objetivo Actual

Validar que el nucleo sea divertido antes de agregar sistemas grandes. El prototipo debe sentirse justo, legible y repetible en partidas 1v1 de pocos minutos.

## Regla Principal

Cada jugador controla piezas de ajedrez. Los movimientos siguen reglas legales de ajedrez, pero se ordenan en tiempo real y cuestan elixir.

## Condiciones De Victoria

- La victoria oficial es por jaque mate.
- El rey no se captura.
- La captura del rey queda descartada como regla final.
- Si no hay movimientos legales y no hay jaque, se considera empate.

## Sistema De Elixir

- Cada jugador tiene elixir.
- Elixir maximo, elixir inicial, regeneracion por segundo, recuperacion por captura, costos de piezas y cooldowns son configurables antes de iniciar.
- Elixir inicial no puede ser mayor al elixir maximo.
- Pendiente: convertir la configuracion suelta en presets claros para jugadores normales.

## Costos Iniciales

- Peon: 1
- Caballo: 3
- Alfil: 3
- Torre: 4
- Reina: 6
- Rey: 3

## Cola De Acciones

- El jugador puede ordenar movimientos en tiempo real.
- El servidor valida y encola movimientos.
- El servidor procesa la cola por ticks.
- Si una accion ya no es legal al procesarse, se descarta.
- Pendiente: decidir cuanto debe ver cada jugador de la cola rival.

## Ticks Y Ritmo

- El servidor procesa la partida en ticks de 250 ms.
- El ritmo debe sentirse en tiempo real, pero legible.
- El cooldown de piezas se muestra en el tablero con un anillo que se llena sobre la pieza.

## Cooldowns

Despues de moverse, una pieza queda temporalmente bloqueada. El servidor rechaza nuevos movimientos de esa pieza hasta que termine su cooldown.

Valores iniciales:

- Peon: 0.75 s.
- Caballo y alfil: 1.5 s.
- Torre: 2.0 s.
- Reina: 3.0 s.
- Rey: 2.0 s.

## Feedback Visual Necesario

El jugador debe entender claramente:

- No tengo elixir.
- La pieza esta en cooldown.
- El movimiento entro a cola.
- El movimiento se proceso.
- El movimiento fue descartado.
- Mi rey esta en jaque.
- La partida termino.

## Multiplayer

- Servidor autoritativo.
- Maximo actual: dos partidas 1v1 simultaneas.
- Sin persistencia de partidas.
- Sin cuentas de usuario.
- Reiniciar requiere acuerdo si hay dos jugadores sentados.

## Modo Practica

- Un jugador puede abrir una partida privada de practica desde el lobby.
- En practica controla ambos colores.
- Blancas siguen abriendo la partida.
- Usa las mismas reglas de elixir, cooldown, promocion y jaque mate.
- No ocupa lugar en las dos partidas online principales.

## Duracion Objetivo

La meta inicial son partidas promedio de 3 a 7 minutos.

## Progresion Cosmetica Local

La version base incluye los conjuntos Clasico y Mana. Los demas cosmeticos se ganan jugando y se guardan sin cuenta:

- Arcano: completar 1 partida.
- Cristal: ganar 3 partidas.
- Elemental: completar 10 partidas.
- Paleta custom: ganar 5 partidas.
- Celestial: ganar 10 partidas.

Las estadisticas viven en `mana-chess-local-stats` y los premios permanentes en `mana-chess-cosmetic-unlocks`. Reiniciar las estadisticas visibles no elimina premios ya ganados. `assets/js/cosmetic_catalog.js` declara los hitos y `assets/js/cosmetic_progression.js` aplica las reglas; los controladores de tienda solo equipan recompensas disponibles.

## No Agregar Todavia

- Habilidades especiales.
- Fog of war.
- Ranking.
- Matchmaking.
- Temporadas.
- Steam/client nativo.

Primero se debe validar que ajedrez + elixir + tiempo real sea divertido sin esconder problemas bajo mas sistemas.

## Roadmap Corto

1. Cerrar reglas base: jaque mate, sin captura de rey.
2. Mejorar estado final y mensajes de partida.
3. Agregar presets de configuracion.
4. Mejorar feedback visual de cola, elixir y descartes.
5. Probar 10 partidas seguidas y ajustar ritmo.
