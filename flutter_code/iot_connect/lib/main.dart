// ignore_for_file: library_private_types_in_public_api, avoid_print

import 'package:firebase_core/firebase_core.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_seria_changed/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:iot_connect/firebase_options.dart';
import 'package:open_settings/open_settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IoT Connect',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
          secondary: Colors.tealAccent,
        ),
        useMaterial3: true,
        fontFamily: 'Poppins',
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.indigo, width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        ),
      ),
      home: const BluetoothScanPage(),
    );
  }
}

class BluetoothScanPage extends StatefulWidget {
  const BluetoothScanPage({Key? key}) : super(key: key);

  @override
  _BluetoothScanPageState createState() => _BluetoothScanPageState();
}

class _BluetoothScanPageState extends State<BluetoothScanPage>
    with SingleTickerProviderStateMixin {
  final List<BluetoothDiscoveryResult> _devicesList = [];
  BluetoothConnection? _bluetoothConnection;
  late final DatabaseReference deviceRef;
  bool _isScanning = false;
  String? _connectedDeviceName;
  bool _devicePowerState = false;
  late TabController _tabController;

  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    deviceRef = FirebaseDatabase.instance.ref("DeviceState");
    _tabController = TabController(length: 2, vsync: this);
    _checkCurrentDeviceState();
  }

  void _checkCurrentDeviceState() {
    deviceRef.child("state").onValue.listen((event) {
      if (event.snapshot.value != null) {
        setState(() {
          _devicePowerState = (event.snapshot.value as int) == 1;
        });
      }
    });
  }

  void _toggleDeviceState(bool newState) {
    deviceRef.child("state").set(newState ? 1 : 0);
    setState(() {
      _devicePowerState = newState;
    });
  }

  Future<void> _checkBluetoothStatus() async {
    bool isEnabled = (await FlutterBluetoothSerial.instance.isEnabled) ?? false;
    if (!isEnabled) {
      _askUserToEnableBluetooth();
    } else {
      _startDiscovery();
    }
  }

  Future<void> _askUserToEnableBluetooth() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Bluetooth is turned off'),
          content: const Text('Please turn on Bluetooth to continue.'),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                OpenSettings.openBluetoothSetting();
              },
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
              child: const Text('Open Settings',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> requestBluetoothScanPermission() async {
    var scanStatus = await Permission.bluetoothScan.status;
    var connectStatus = await Permission.bluetoothConnect.status;

    if (scanStatus.isDenied || connectStatus.isDenied) {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();

      if (statuses[Permission.bluetoothScan]!.isGranted &&
          statuses[Permission.bluetoothConnect]!.isGranted) {
        _checkBluetoothStatus();
      } else {
        _showNotGrantedAlert();
      }
    } else if (scanStatus.isPermanentlyDenied ||
        connectStatus.isPermanentlyDenied) {
      openAppSettings();
    } else {
      _checkBluetoothStatus();
    }
  }

  void _startDiscovery() async {
    setState(() {
      _devicesList.clear();
      _isScanning = true;
    });

    await FlutterBluetoothSerial.instance.cancelDiscovery();

    try {
      FlutterBluetoothSerial.instance.startDiscovery().listen(
        (device) {
          setState(() {
            // Only add devices with names (filters out most non-IoT devices)
            if (device.device.name != null && device.device.name!.isNotEmpty) {
              _devicesList.add(device);
            }
          });
        },
        onDone: () {
          setState(() {
            _isScanning = false;
          });
        },
        onError: (error) {
          setState(() {
            _isScanning = false;
          });
          _showErrorSnackBar('Error scanning: $error');
        },
      );
    } catch (e) {
      setState(() {
        _isScanning = false;
      });
      _showErrorSnackBar('Failed to start discovery: $e');
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      _disconnect();

      setState(() {
        _connectedDeviceName = 'Connecting to ${device.name}...';
      });

      final BluetoothConnection connection =
          await BluetoothConnection.toAddress(device.address);

      setState(() {
        _bluetoothConnection = connection;
        _connectedDeviceName = device.name;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to ${device.name}'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Switch to control tab after successful connection
      _tabController.animateTo(1);
    } catch (error) {
      setState(() {
        _connectedDeviceName = null;
      });
      _showErrorSnackBar('Failed to connect: $error');
    }
  }

  void _sendData(String data) {
    try {
      if (_bluetoothConnection != null) {
        _bluetoothConnection!.output.add(Uint8List.fromList(data.codeUnits));
        _bluetoothConnection!.output.allSent.then((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('WiFi credentials sent successfully'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        });
      } else {
        _showNotConnectedAlert();
      }
    } catch (error) {
      if (error is StateError) {
        _showNotPairedAlert();
      } else {
        _showErrorSnackBar('Error sending data: $error');
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showNotConnectedAlert() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Not Connected'),
          content: const Text(
              'Please connect to a device before sending WiFi credentials.'),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actions: <Widget>[
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                _tabController.animateTo(0); // Switch to scan tab
              },
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
              child: const Text('Connect Device',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showNotGrantedAlert() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Permission Required'),
          content: const Text(
              'Bluetooth permissions are required to discover and connect to devices.'),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
              child: const Text('Open Settings',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showNotPairedAlert() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Device Not Paired'),
          content: const Text(
              'Please pair with a Bluetooth device before sending data.'),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actions: <Widget>[
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                OpenSettings.openBluetoothSetting();
              },
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
              child: const Text('Open Bluetooth Settings',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _disconnect() {
    if (_bluetoothConnection != null) {
      _bluetoothConnection!.dispose();
      _bluetoothConnection = null;
      setState(() {
        _connectedDeviceName = null;
      });
    }
  }

  @override
  void dispose() {
    _disconnect();
    _tabController.dispose();
    _ssidController.dispose();
    _passwordController.dispose();
    FirebaseDatabase.instance.goOffline(); // Close Firebase connection
    super.dispose();
  }

  Future<void> connectToFirebase() async {
    try {
      deviceRef.once().then((DatabaseEvent event) {
        DataSnapshot snapshot = event.snapshot;
        print('Connected to Firebase: ${snapshot.value}');
      });
    } catch (error) {
      _showErrorSnackBar('Error connecting to Firebase: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IoT Connect',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              icon: Icon(Icons.bluetooth_searching),
              text: 'Discover',
            ),
            Tab(
              icon: Icon(Icons.settings_remote),
              text: 'Control',
            ),
          ],
          indicatorColor: Theme.of(context).colorScheme.primary,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: Colors.grey,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Discovery Tab
          _buildDiscoveryTab(),

          // Control Tab
          _buildControlTab(),
        ],
      ),
    );
  }

  Widget _buildDiscoveryTab() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Colors.indigo.shade50],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text(
                      'Discover Devices',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Scan for nearby IoT devices and connect to them',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _isScanning
                          ? null
                          : () async {
                              await requestBluetoothScanPermission();
                              await connectToFirebase();
                            },
                      icon: _isScanning
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.search),
                      label: Text(_isScanning ? 'Scanning...' : 'Start Scan'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Connection Status
            if (_connectedDeviceName != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bluetooth_connected, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Connected to: $_connectedDeviceName',
                        style: const TextStyle(color: Colors.green),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          size: 18, color: Colors.green),
                      onPressed: _disconnect,
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // Devices List Title
            Row(
              children: [
                const Icon(Icons.devices, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  'Available Devices',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (_isScanning)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 8),

            // Devices List
            Expanded(
              child: _devicesList.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.bluetooth_disabled,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _isScanning
                                ? 'Searching for devices...'
                                : 'No devices found',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          if (!_isScanning) ...[
                            const SizedBox(height: 24),
                            TextButton(
                              onPressed: () async {
                                await requestBluetoothScanPermission();
                              },
                              child: const Text('Tap to Scan Again'),
                            ),
                          ]
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _devicesList.length,
                      itemBuilder: (context, index) {
                        final device = _devicesList[index].device;
                        final rssi = _devicesList[index].rssi;

                        // Calculate signal strength indicator
                        int bars = 0;
                        if (rssi >= -60) {
                          bars = 3; // Strong signal
                        } else if (rssi >= -70) {
                          bars = 2; // Medium signal
                        } else {
                          bars = 1; // Weak signal
                        }

                        return Card(
                          elevation: 1,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: device.isBonded
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.3)
                                  : Colors.transparent,
                              width: device.isBonded ? 1 : 0,
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withOpacity(0.1),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Icon(
                                device.isBonded
                                    ? Icons.bluetooth_connected
                                    : Icons.bluetooth,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            title: Text(
                              device.name ?? 'Unknown Device',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Row(
                              children: [
                                Text(
                                  device.isBonded ? 'Paired' : 'Not paired',
                                  style: TextStyle(
                                    color: device.isBonded
                                        ? Colors.green
                                        : Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Row(
                                  children: List.generate(3, (i) {
                                    return Icon(
                                      Icons.signal_cellular_alt,
                                      size: 14,
                                      color: i < bars
                                          ? Colors.green[600]
                                          : Colors.grey[300],
                                    );
                                  }),
                                ),
                              ],
                            ),
                            trailing: ElevatedButton(
                              onPressed: () => _connectToDevice(device),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: device.isBonded
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey[200],
                                foregroundColor: device.isBonded
                                    ? Colors.white
                                    : Colors.black87,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                              ),
                              child: const Text('Connect'),
                            ),
                            onTap: () => _connectToDevice(device),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlTab() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Colors.indigo.shade50],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Device Status Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _connectedDeviceName != null
                                ? Colors.green
                                : Colors.grey,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _connectedDeviceName != null
                              ? 'Connected to $_connectedDeviceName'
                              : 'No Device Connected',
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: _devicePowerState
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey[300],
                        borderRadius: BorderRadius.circular(60),
                        boxShadow: _devicePowerState
                            ? [
                                BoxShadow(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.3),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                ),
                              ]
                            : null,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(60),
                          onTap: _connectedDeviceName != null
                              ? () => _toggleDeviceState(!_devicePowerState)
                              : () => _showNotConnectedAlert(),
                          child: Icon(
                            Icons.power_settings_new,
                            size: 60,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _devicePowerState ? 'Device is ON' : 'Device is OFF',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color:
                            _devicePowerState ? Colors.green : Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap the power button to toggle the device',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // WiFi Configuration
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.wifi, color: Colors.indigo),
                        SizedBox(width: 8),
                        Text(
                          'WiFi Configuration',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _ssidController,
                      decoration: const InputDecoration(
                        labelText: 'WiFi Network Name (SSID)',
                        prefixIcon: Icon(Icons.router),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'WiFi Password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _connectedDeviceName != null
                          ? () {
                              if (_ssidController.text.isEmpty) {
                                _showErrorSnackBar('Please enter a WiFi name');
                                return;
                              }
                              String ssid = _ssidController.text;
                              String password = _passwordController.text;
                              _sendData('$ssid:$password');
                            }
                          : () => _showNotConnectedAlert(),
                      icon: const Icon(Icons.send),
                      label: const Text('Send WiFi Credentials'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // No device connected message
            if (_connectedDeviceName == null)
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.device_unknown,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No device connected',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () {
                        _tabController.animateTo(0);
                      },
                      icon: const Icon(Icons.search),
                      label: const Text('Go to Discover'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
