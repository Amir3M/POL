package com.arman.firefoxvpn

import android.annotation.TargetApi
import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.TetheringInterface
import android.net.TetheringManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import org.json.JSONObject
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.concurrent.Executor

/**
 * A foreground proxy session may share an authenticated listener on one
 * verified local Wi-Fi network. All state here belongs to the main thread.
 * Sharing is never restored from disk.
 */
internal object AndroidShareProxy {
    private val main = Handler(Looper.getMainLooper())
    private var service: CoreService? = null
    private var enabled = false
    private var endpoint: Endpoint? = null
    private var error: String? = null
    private var watcher: NetworkWatcher? = null
    private var choices = emptyList<BindAddress>()
    private var preferred: BindAddress? = null

    private data class BindAddress(
        val address: String,
        val prefix: Int,
        val interfaceName: String,
        val network: Network?,
        val type: String,
    )

    private data class Endpoint(
        val binding: BindAddress,
        val port: Int,
        val username: String,
        val password: String,
    )

    fun attach(active: CoreService) {
        service = active
        refresh()
    }

    fun detach(active: CoreService) {
        if (service !== active) return
        disable()
        service = null
    }

    fun setEnabled(context: Context, on: Boolean): Map<String, Any?> {
        if (!on) {
            disable()
        } else if (CoreService.usesVpn(context)) {
            disable()
            error = "proxy_mode_required"
        } else {
            enabled = true
            refresh()
        }
        return status()
    }

    fun status(): Map<String, Any?> {
        val current = endpoint
        return mapOf(
            "enabled" to enabled,
            "active" to (current != null),
            "endpoints" to if (current == null) emptyList() else listOf(
                mapOf(
                    "address" to current.binding.address,
                    "port" to current.port,
                    "networkType" to current.binding.type,
                    "username" to current.username,
                    "password" to current.password,
                ),
            ),
            "choices" to choices.map { mapOf("address" to it.address, "networkType" to it.type) },
            "error" to error,
        )
    }

    fun selectEndpoint(address: String): Map<String, Any?> {
        val selected = choices.firstOrNull { it.address == address }
        if (!enabled || selected == null) {
            error = "endpoint_unavailable"
        } else {
            preferred = selected
            refresh()
        }
        return status()
    }

    fun rotateCredentials(): Map<String, Any?> {
        val current = endpoint
        if (enabled && current != null) {
            try {
                endpoint = decodeEndpoint(current.binding, mobile.Mobile.rotateSharedProxyCredentials())
                error = null
            } catch (_: Exception) {
                closeEndpoint()
                error = "bind_failed"
            }
        }
        return status()
    }

    fun disable() {
        enabled = false
        error = null
        watcher?.close()
        watcher = null
        choices = emptyList()
        preferred = null
        closeEndpoint()
    }

    private fun closeEndpoint() {
        endpoint = null
        if (mobile.Mobile.running()) {
            // The Go daemon also closes the listener before stopping the engine.
            runCatching { mobile.Mobile.setSharedProxy("", 0) }
        }
    }

    /** Also called by CoreService's existing foreground polling loop. */
    fun refresh() {
        if (!enabled) return
        val current = service ?: return
        if (!CoreService.on || CoreService.usesVpn(current)) {
            disable()
            return
        }
        val monitor = watcher ?: NetworkWatcher(current).also {
            watcher = it
            it.start()
        }
        choices = try {
            monitor.bindings()
        } catch (_: Exception) {
            emptyList()
        }
        val selected = preferred
        val binding = choices.minWithOrNull(
            compareBy<BindAddress>(
                { it != selected },
                { selected == null || it.interfaceName != selected.interfaceName || it.type != selected.type },
                { it.type != "hotspot" },
                { it != endpoint?.binding },
                { it.interfaceName },
                { it.address },
            ),
        )
        if (binding == null) {
            if (endpoint != null) closeEndpoint()
            error = "no_local_network"
            return
        }

        if (endpoint?.let { it.binding != binding } == true) closeEndpoint()
        try {
            endpoint = decodeEndpoint(binding, mobile.Mobile.setSharedProxy(binding.address, binding.prefix))
            error = null
        } catch (_: Exception) {
            closeEndpoint()
            // Do not expose exceptions from sockets or credential handling.
            error = "bind_failed"
        }
    }

    private fun decodeEndpoint(binding: BindAddress, response: String): Endpoint {
        val data = JSONObject(response)
        check(data.getString("address") == binding.address)
        val port = data.getInt("port")
        val username = data.getString("username")
        val password = data.getString("password")
        check(port in 1..65535 && username.isNotEmpty() && password.isNotEmpty())
        return Endpoint(binding, port, username, password)
    }

    private class NetworkWatcher(private val context: Context) {
        private val connectivity = context.getSystemService(ConnectivityManager::class.java)
        private val callbacks = mutableListOf<ConnectivityManager.NetworkCallback>()
        private val readBinding = Runnable {
            if (watcher === this) refresh()
        }
        private var hotspotWatcher: AutoCloseable? = null
        private var tetheredWifi = emptySet<String>()

        fun start() {
            register(NetworkRequest.Builder().addTransportType(NetworkCapabilities.TRANSPORT_WIFI).build())
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
                register(
                    NetworkRequest.Builder()
                        .clearCapabilities()
                        .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                        .addCapability(NetworkCapabilities.NET_CAPABILITY_LOCAL_NETWORK)
                        .build(),
                )
            }
            if (Build.VERSION.SDK_INT >= 36) {
                hotspotWatcher = runCatching {
                    watchTethering(context) { names ->
                        if (watcher === this) {
                            tetheredWifi = names
                            val selected = endpoint?.binding
                            if (selected?.type == "hotspot" && selected.network == null &&
                                selected.interfaceName !in names
                            ) closeEndpoint()
                            changed()
                        }
                    }
                }.getOrNull()
            }
        }

        private fun register(request: NetworkRequest) {
            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) = changed()

                override fun onLost(network: Network) {
                    main.post {
                        if (watcher === this@NetworkWatcher) {
                            if (endpoint?.binding?.network == network) closeEndpoint()
                            changed()
                        }
                    }
                }

                override fun onLinkPropertiesChanged(network: Network, properties: LinkProperties) = changed()

                override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) = changed()
            }
            runCatching {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    connectivity.registerNetworkCallback(request, callback, main)
                } else {
                    connectivity.registerNetworkCallback(request, callback)
                }
                callbacks.add(callback)
            }
        }

        private fun changed() {
            // Rediscover outside the platform callback.
            main.removeCallbacks(readBinding)
            main.post(readBinding)
        }

        fun close() {
            callbacks.forEach { runCatching { connectivity.unregisterNetworkCallback(it) } }
            callbacks.clear()
            runCatching { hotspotWatcher?.close() }
            hotspotWatcher = null
            main.removeCallbacks(readBinding)
            tetheredWifi = emptySet()
        }

        @Suppress("DEPRECATION") // Snapshot avoids assuming the default network is Wi-Fi.
        fun bindings(): List<BindAddress> {
            val candidates = connectivity.allNetworks.flatMap { network ->
                val capabilities = connectivity.getNetworkCapabilities(network) ?: return@flatMap emptyList()
                if (!capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                    capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) ||
                    capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)
                ) return@flatMap emptyList()
                val properties = connectivity.getLinkProperties(network) ?: return@flatMap emptyList()
                val name = properties.interfaceName ?: return@flatMap emptyList()
                val type = if (name in tetheredWifi ||
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM &&
                    capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_LOCAL_NETWORK)
                ) "hotspot" else "wifi"
                properties.linkAddresses.mapNotNull { link ->
                    privateIpv4(link.address as? Inet4Address, link.prefixLength)
                        ?.let { BindAddress(it, link.prefixLength, name, network, type) }
                }
            }
            val verifiedHotspots = tetheredWifi.flatMap { name ->
                val networkInterface = NetworkInterface.getByName(name) ?: return@flatMap emptyList()
                if (!networkInterface.isUp || networkInterface.isLoopback) return@flatMap emptyList()
                networkInterface.interfaceAddresses.mapNotNull { link ->
                    val prefix = link.networkPrefixLength.toInt()
                    privateIpv4(link.address as? Inet4Address, prefix)
                        ?.let { BindAddress(it, prefix, name, null, "hotspot") }
                }
            }
            return (candidates + verifiedHotspots)
                .groupBy { it.address }
                .values
                .mapNotNull { sameIp ->
                    // A socket cannot distinguish two interfaces with the same IP.
                    sameIp.first().takeIf { sameIp.all { option -> option.interfaceName == it.interfaceName } }
                }
                .sortedWith(compareBy({ it.type }, { it.address }))
        }
    }

    @TargetApi(36)
    private fun watchTethering(
        context: Context,
        update: (Set<String>) -> Unit,
    ): AutoCloseable {
        val manager = context.getSystemService(TetheringManager::class.java)
        val callback = object : TetheringManager.TetheringEventCallback {
            override fun onTetheredInterfacesChanged(interfaces: MutableSet<TetheringInterface>) {
                update(interfaces.filter { it.type == TetheringManager.TETHERING_WIFI }
                    .map { it.getInterface() }.toSet())
            }
        }
        manager.registerTetheringEventCallback(Executor { main.post(it) }, callback)
        return AutoCloseable { manager.unregisterTetheringEventCallback(callback) }
    }

    private fun privateIpv4(address: Inet4Address?, prefix: Int): String? {
        val local = address ?: return null
        val bytes = local.address
        val first = bytes[0].toInt() and 0xff
        val second = bytes[1].toInt() and 0xff
        val privatePrefix = when {
            first == 10 -> 8
            first == 172 && second in 16..31 -> 12
            first == 192 && second == 168 -> 16
            else -> return null
        }
        return if (prefix in privatePrefix..30) local.hostAddress else null
    }
}
