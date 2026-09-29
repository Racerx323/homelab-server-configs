/* Review-only override from smartmontools issue #648, comment 5894223773.
 * Supply explicitly with -B +FILE only during an approved bounded test.
 * Do not install in a default database location during Webmin observation.
 */
{ "USB: ; JMicron JMS583",
  "0x152d:0x0583",
  "0x0213",
  "",
  "-d sntjmicron"
},
