package tw.avianjay.taiwanbus.wearos.data

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BusApiServiceTest {
    @Test
    fun testFetchRouteDetail() = runBlocking {
        val routeId = "KEE052601"
        val provider = "KEE"

        val detail = BusApiService.fetchRouteDetail(null, routeId, provider)
        println("Route ID: ${detail.routeId}")
        println("Route Name: ${detail.routeName}")
        println("Provider: ${detail.provider}")
        println("Paths count: ${detail.paths.size}")
        
        assertNotNull(detail)
        assertTrue(detail.paths.isNotEmpty())
        for (path in detail.paths) {
            println("  Path ID: ${path.pathId}, Name: ${path.name}")
            assertTrue(path.stops.isNotEmpty())
            for (stop in path.stops.take(5)) {
                println("    Stop ID: ${stop.stopId}, Name: '${stop.name}', ETA: ${stop.etaText}")
                assertFalse("Stop name should not be blank", stop.name.isBlank())
            }
        }
    }
}
