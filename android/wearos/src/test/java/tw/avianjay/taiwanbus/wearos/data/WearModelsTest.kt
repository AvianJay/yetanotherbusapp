package tw.avianjay.taiwanbus.wearos.data

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class WearModelsTest {
    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun favoritePayloadDecodesAllThreeFavoriteTypes() {
        val payload = json.decodeFromString<FavoritePayload>(
            """
            {
              "favorites": [
                {"id":"route:tpe:R1","type":"route","provider":"tpe","routeKey":1,"routeId":"R1","routeName":"307","routeDescription":"往板橋"},
                {"id":"station:tpe:S1","type":"station","provider":"tpe","stationId":"S1","stationName":"臺北車站"},
                {"id":"tpe:1:0:10","type":"boarding","provider":"tpe","routeKey":1,"pathId":0,"stopId":10,"routeId":"R1","routeName":"307","stopName":"臺北車站"}
              ]
            }
            """.trimIndent(),
        )

        assertEquals(listOf("route", "station", "boarding"), payload.favorites.map { it.type })
        assertEquals("往板橋", payload.favorites[0].displayStopName)
        assertEquals("臺北車站", payload.favorites[1].displayRouteName)
        assertNull(payload.favorites[0].realtimeRouteId)
        assertNull(payload.favorites[1].realtimeRouteId)
        assertEquals("R1", payload.favorites[2].realtimeRouteId)
    }

    @Test
    fun legacyFavoriteDefaultsToBoarding() {
        val favorite = json.decodeFromString<FavoriteStop>(
            """{"id":"tpe:1:0:10","provider":"tpe","routeKey":1,"pathId":0,"stopId":10,"routeId":"R1"}""",
        )

        assertEquals("boarding", favorite.type)
        assertEquals("R1", favorite.realtimeRouteId)
    }
}
