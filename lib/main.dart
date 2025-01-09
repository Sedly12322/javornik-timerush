import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';  // Firebase Core
import 'package:firebase_auth/firebase_auth.dart'; // Firebase Auth
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart'; // Import knihovny


void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Ujistíme se, že inicializace Firebase probíhá před spuštěním aplikace
  await Firebase.initializeApp(); // Inicializace Firebase
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(), // Sledování stavu přihlášení
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          if (snapshot.hasData) {
            return MainScreen(); // Pokud je uživatel přihlášený, přesměrujeme ho na hlavní obrazovku
          } else {
            return HomeScreen(); // Pokud není přihlášený, zobrazíme obrazovku přihlášení
          }
        }
        // Při čekání na data zobrazíme nějaký indikátor načítání
        return CircularProgressIndicator();
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController(); // TextController pro uživatelské jméno
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isLoginMode = false; // Přidáme tuto proměnnou pro určení, zda jsme v režimu přihlášení nebo registrace

  // Funkce pro registraci uživatele
  Future<void> _register() async {
    try {
      // 2. Kontrola, zda uživatelské jméno již existuje v Firestore
      final usernameExists = await _checkIfUsernameExists(_usernameController.text);
      if (usernameExists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Uživatelské jméno již existuje!')),
        );
        return;
      }

      // 3. Pokud vše probíhá v pořádku, registrace uživatele
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text,
        password: _passwordController.text,
      );

      // 4. Uložení uživatelského jména do Firestore
      FirebaseFirestore.instance.collection('users').doc(userCredential.user?.uid).set({
        'username': _usernameController.text,
        'email': _emailController.text,
      });

      print('Uživatel registrován');
      _navigateToMainScreen(); // Přesměrování na hlavní obrazovku po registraci
    } on FirebaseAuthException catch (e) {
      print('Chyba při registraci: ${e.message}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('E-mail již existuje nebo zadáváte špatnou e-mailovou adresu!')),
      );
    } catch (e) {
      print('Neznámá chyba při registraci: $e');
    }
  }

// Funkce pro kontrolu uživatelského jména
  Future<bool> _checkIfUsernameExists(String username) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isEqualTo: username)
          .get();
      return snapshot.docs.isNotEmpty; // Pokud je nějaký dokument s tímto jménem, uživatel existuje
    } catch (e) {
      print('Chyba při kontrole uživatelského jména: $e');
      return false;
    }
  }


  Future<void> _login() async {
    try {
      // Nejprve hledáme uživatele podle uživatelského jména
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isEqualTo: _usernameController.text) // Hledáme podle uživatelského jména
          .get();

      if (snapshot.docs.isEmpty) {
        // Uživatel s tímto jménem neexistuje
        print('Uživatel s tímto jménem neexistuje.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Uživatel s tímto jménem neexistuje.')),
        );
        return;
      }

      // Získáme e-mail z dokumentu uživatele
      String userEmail = snapshot.docs.first['email'];

      // Přihlásíme se pomocí e-mailu a hesla
      await _auth.signInWithEmailAndPassword(
        email: userEmail,
        password: _passwordController.text,
      );

      print('Uživatel přihlášen');
      _navigateToMainScreen(); // Přesměrování na hlavní obrazovku po přihlášení
    } on FirebaseAuthException catch (e) {
      // Různé možné chyby při přihlášení
      String errorMessage = '';
      if (e.code == 'user-not-found') {
        errorMessage = 'Účet s tímto e-mailem nebyl nalezen.';
      } else if (e.code == 'wrong-password') {
        errorMessage = 'Špatné heslo. Zkuste to znovu.';
      } else {
        errorMessage = 'Došlo k chybě při přihlášení: ${e.message}';
      }

      // Zobrazení chybové zprávy pomocí SnackBar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    } catch (e) {
      print('Neznámá chyba při přihlášení: $e');
      // Zobrazení obecných chybových zpráv
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Došlo k neočekávané chybě.')),
      );
    }
  }


  // Funkce pro přesměrování na hlavní obrazovku
  void _navigateToMainScreen() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => MainScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Image.asset(
          'assets/images/logofinal.png',
          width: 300.0,
          height: 200.0,
        ),
        centerTitle: true,
        backgroundColor: Color.fromRGBO(200, 228, 255, 1),
        toolbarHeight: 130,
      ),
      body: Container(
        height: 1000,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color.fromRGBO(200, 228, 255, 1), Colors.greenAccent],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Align(
                alignment: Alignment.topCenter,
                child: Image.asset(
                  'assets/images/logo2-transformed.png',
                  width: 150.0,
                  height: 120.0,
                ),
              ),
              SizedBox(height: 10),

              Container(
                padding: EdgeInsets.all(20.0),
                width: 300,
                height: 413, // Zvýšení výšky pro zahrnutí jména
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Text(
                      _isLoginMode ? 'Přihlášení uživatele' : 'Registrace uživatele', // Dynamický text
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 20),
                    // Zobrazí pole pro uživatelské jméno pouze v režimu registrace
                    TextField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        labelText: 'Uživatelské jméno',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SizedBox(height: 20),
                    // Zobrazí pole pro e-mail pouze v režimu registrace
                    if (!_isLoginMode)
                      TextField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          labelText: 'E-mail',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    SizedBox(height: 20),
                    // Zobrazí pole pro heslo v obou režimech
                    TextField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Heslo',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                    ),
                    SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _isLoginMode ? _login : _register, // Podmíněné volání funkce
                      child: Text(_isLoginMode ? 'Přihlásit se' : 'Registrovat se'), // Dynamický text
                    ),
                    // Tlačítko pro přepnutí mezi režimy
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isLoginMode = !_isLoginMode; // Přepne režim
                        });
                      },
                      child: Text(_isLoginMode
                          ? 'Nemáte účet? Zaregistrujte se'
                          : 'Máte účet? Přihlaste se'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Hlavní stránka s tlačítkem pro odhlášení
class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  List<Map<String, dynamic>> mountains = []; // Seznam hor načítaný z Firestore
  List<Map<String, dynamic>>? _selectedMountainRoutes = []; // Trasy pro vybranou horu
  String? _selectedMountain;
  String? _selectedRoute; // Vybraná trasa
  LatLng _currentPosition = LatLng(50.0755, 14.4378); // Praha, default
  String? _username;

  @override
  void initState() {
    super.initState();
    _loadMountains();  // Načítání hor z Firestore
    _loadUsername();
  }

  // Funkce pro načítání uživatelského jména z Firestore
  Future<void> _loadUsername() async {
    User? user = _auth.currentUser;
    if (user != null) {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      setState(() {
        _username = userDoc['username'];  // Načítání uživatelského jména
      });
    }
  }

  LatLngBounds _getRouteBounds(List<LatLng> route) {
    double minLat = route[0].latitude;
    double maxLat = route[0].latitude;
    double minLng = route[0].longitude;
    double maxLng = route[0].longitude;

    for (var point in route) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    return LatLngBounds(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );
  }


  // Funkce pro načítání hor z Firestore (včetně tras)
  Future<void> _loadMountains() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('mountains').get();
      final List<Map<String, dynamic>> loadedMountains = [];
      for (var doc in snapshot.docs) {
        String name = doc['name'];
        double lat = doc['lat'];
        double lng = doc['lng'];

        final routesSnapshot = await FirebaseFirestore.instance
            .collection('mountains')
            .doc(doc.id)
            .collection('trails')
            .get();

        List<Map<String, dynamic>> routes = routesSnapshot.docs.map((routeDoc) {
          return {
            'name': routeDoc['name'], // Název trasy
            'start_lat': routeDoc['start_lat'],
            'start_lng': routeDoc['start_lng'],
            'end_lat': routeDoc['end_lat'],
            'end_lng': routeDoc['end_lng'],
            'polyline': routeDoc['polyline'],
          };
        }).toList();

        loadedMountains.add({
          'name': name,
          'lat': lat,
          'lng': lng,
          'routes': routes,
        });
      }

      setState(() {
        mountains = loadedMountains;
      });
    } catch (e) {
      print('Chyba při načítání hor a tras: $e');
    }
  }

  // Funkce pro načítání tras pro vybranou horu
  void _loadRoutesForSelectedMountain() {
    if (_selectedMountain == null) {
      _selectedMountainRoutes = [];
    } else {
      final selectedMountainData = mountains.firstWhere(
            (mountain) => mountain['name'] == _selectedMountain,
      );
      _selectedMountainRoutes = List.from(selectedMountainData['routes']);
    }
    setState(() {});
  }

  Future<List<LatLng>> _decodePolyline(String polyline) async {
    PolylinePoints polylinePoints = PolylinePoints();

    // Dekóduje polyline
    List<PointLatLng> decodedPoints = polylinePoints.decodePolyline(polyline);

    // Převede na seznam LatLng
    return decodedPoints
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList();
  }

  // Funkce pro zobrazení tras na mapě
  Future<List<LatLng>> _getRouteForSelectedRoute() async {
    if (_selectedRoute == null) return [];

    final selectedRouteData = _selectedMountainRoutes!.firstWhere(
          (route) => route['name'] == _selectedRoute,
    );
    String polyline = selectedRouteData['polyline'];

    print('Polyline: $polyline'); // Zkontrolujte, že máte platnou polyline
    return await _decodePolyline(polyline);
  }


  // Funkce pro navigaci do nové obrazovky
  void _navigateToNavigationScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NavigationScreen(
          currentPosition: _currentPosition,
          selectedRoute: _selectedRoute!,
          selectedMountain: _selectedMountain!,
          selectedPolyline: _getRouteForSelectedRoute(), // Předání polyline trasy
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Mapa s výběrem destinace"),
        actions: [
          IconButton(
            icon: Icon(Icons.exit_to_app),
            onPressed: () async {
              await _auth.signOut();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => HomeScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_username != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('Ahoj, $_username!', style: TextStyle(fontSize: 24)),
            ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    value: _selectedMountain,
                    hint: Text('Vyberte horu'),
                    items: mountains.map((mountain) {
                      return DropdownMenuItem<String>(
                        value: mountain['name'],
                        child: Text(mountain['name']),
                      );
                    }).toList(),
                    onChanged: (newValue) {
                      setState(() {
                        _selectedMountain = newValue;
                        _loadRoutesForSelectedMountain();
                      });
                    },
                  ),
                ),
                SizedBox(width: 20),
                Expanded(
                  child: DropdownButton<String>(
                    value: _selectedRoute,
                    hint: Text('Vyberte trasu'),
                    items: _selectedMountainRoutes?.map((route) {
                      return DropdownMenuItem<String>(
                        value: route['name'],
                        child: Text(route['name']),
                      );
                    }).toList(),
                    onChanged: (newValue) {
                      setState(() {
                        _selectedRoute = newValue;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<LatLng>>(
              future: _getRouteForSelectedRoute(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(child: Text('Chyba při získávání trasy'));
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(child: Text('Vyberte trasu pro zobrazení'));
                }

                final route = snapshot.data!;
                LatLngBounds bounds = _getRouteBounds(route);

                return FlutterMap(
                  options: MapOptions(
                    initialCenter: bounds.center,
                    initialZoom: 14.0,
                    minZoom: 14.0,
                    maxZoom: 18.0,
                    interactionOptions: InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                      subdomains: ['a', 'b', 'c'],
                    ),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: route,
                          strokeWidth: 4.0,
                          color: Colors.blue,
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          if (_selectedRoute != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton(
                onPressed: _navigateToNavigationScreen,
                child: Text("Navigovat"),
              ),
            ),
        ],
      ),
    );
  }
}

class NavigationScreen extends StatefulWidget {
  final LatLng currentPosition;
  final String selectedRoute;
  final String selectedMountain;
  final Future<List<LatLng>> selectedPolyline;

  NavigationScreen({
    required this.currentPosition,
    required this.selectedRoute,
    required this.selectedMountain,
    required this.selectedPolyline,
  });

  @override
  _NavigationScreenState createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  bool _serviceEnabled = false;
  LocationPermission? _permission;
  late StreamSubscription<Position> _positionStreamSubscription;
  Position? _currentPosition;
  bool _isNearStart = false; // Flag pro kontrolu blízkosti startu
  bool _isTimerRunning = false; // Stav stopky (běží nebo pozastavená)
  Stopwatch _stopwatch = Stopwatch(); // Stopky
  late LatLng _startPoint; // Startovací bod trasy
  late LatLng _endPoint; // Poslední bod trasy
  Timer? _timer; // Timer pro pravidelnou aktualizaci času
  String _elapsedTime = ""; // Text pro zobrazení uběhlého času po zastavení

  @override
  void initState() {
    super.initState();
    _checkGpsPermission();
  }

  Future<void> _saveClimbOutput(String userId, String mountainId, String routeId, String time) async {
    try {
      // Hledáme existující záznam pro daného uživatele, horu a trasu
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('climbs')
          .where('mountainID', isEqualTo: mountainId)
          .where('trailID', isEqualTo: routeId)
          .get();

      if (snapshot.docs.isNotEmpty) {
        // Existuje záznam, porovnáme čas
        DocumentSnapshot doc = snapshot.docs.first;
        String existingTime = doc['time']; // Předchozí čas, který je uložen v databázi

        // Převeď čas na Duration pro porovnání
        Duration newTimeDuration = _parseTimeToDuration(time);
        Duration existingTimeDuration = _parseTimeToDuration(existingTime);

        // Porovnáme časy: pokud je nový čas lepší (kratší), přepíšeme
        if (newTimeDuration < existingTimeDuration) {
          // Aktualizace záznamu
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('climbs')
              .doc(doc.id)  // ID existujícího záznamu
              .update({
            'time': time,  // Nový čas
            'date': DateTime.now(),  // Datum aktualizace
          });

          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Výstup byl aktualizován!'),
          ));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Nový čas není lepší než předchozí výstup.'),
          ));
        }
      } else {
        // Pokud neexistuje záznam, uložíme nový výstup
        await FirebaseFirestore.instance.collection('users').doc(userId)
            .collection('climbs').add({
          'mountainID': mountainId,
          'trailID': routeId,
          'time': time,
          'date': DateTime.now(),
        });

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Výstup úspěšně uložen!'),
        ));
      }
    } catch (e) {
      print("Chyba při ukládání výstupu: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Chyba při ukládání výstupu.'),
      ));
    }
  }

  Duration _parseTimeToDuration(String time) {
    // Předpokládáme, že čas je ve formátu "mm:ss"
    List<String> parts = time.split(':');
    int minutes = int.parse(parts[0]);
    int seconds = int.parse(parts[1]);
    return Duration(minutes: minutes, seconds: seconds);
  }




  // Funkce pro výpočet vzdálenosti mezi dvěma body
  double _calculateDistance(LatLng point1, LatLng point2) {
    return Geolocator.distanceBetween(
      point1.latitude, point1.longitude,
      point2.latitude, point2.longitude,
    );
  }

  // Funkce pro kontrolu, zda je uživatel blízko startu trasy
  void _checkProximityToStart(LatLng startPoint) {
    if (_currentPosition != null) {
      double distance = _calculateDistance(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        startPoint,
      );
      setState(() {
        _isNearStart = distance < 10; // Pokud je vzdálenost menší než 10 metrů, zobrazí se tlačítko Start
      });
    }
  }

  void _checkProximityToEnd(LatLng endPoint) {
    if (_currentPosition != null) {
      double distance = _calculateDistance(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        endPoint,
      );

      // Pokud je uživatel blízko posledního bodu trasy, zastavíme stopky
      if (distance < 10 && _isTimerRunning) {
        setState(() {
          _stopwatch.stop();
          _isTimerRunning = false;
          _elapsedTime = _formatElapsedTime(_stopwatch.elapsed); // Uložení uběhlého času
        });

        // Zastavit Timer
        _timer?.cancel();
        print("Stopky zastaveny. Uživatelská poloha: $distance m od posledního bodu.");

        // Zavolání zápisu do Firestore
        // Předpokládejme, že už máš nějaké ID uživatele, tady použijeme "userId"
        String userId = FirebaseAuth.instance.currentUser!.uid;  // To by měl být ID přihlášeného uživatele
        _saveClimbOutput(userId, widget.selectedMountain, widget.selectedRoute, _elapsedTime);
      }
    }
  }


  // Funkce pro kontrolu GPS a oprávnění
  Future<void> _checkGpsPermission() async {
    _serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!_serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('GPS služba není povolena!'),
      ));
      return;
    }

    _permission = await Geolocator.checkPermission();
    if (_permission == LocationPermission.denied) {
      _permission = await Geolocator.requestPermission();
      if (_permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Bez povolení k poloze nemohu pokračovat.'),
        ));
        return;
      }
    }

    _getPositionStream();
  }

  // Stream pro aktuální pozici
  void _getPositionStream() {
    LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high, // Nastavení vysoké přesnosti
      distanceFilter: 1, // Zajistíme, že budeme dostávat polohu každých 1 metr (můžete přizpůsobit)
    );

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      setState(() {
        _currentPosition = position;
      });

      // Kontrola blízkosti k startovnímu bodu a poslednímu bodu trasy
      if (_currentPosition != null) {
        _checkProximityToStart(_startPoint);
        _checkProximityToEnd(_endPoint);
      }
    });
  }

  // Funkce pro spuštění stopky a Timeru
  void _startTimer() {
    setState(() {
      _stopwatch.start();
      _isTimerRunning = true;
    });

    // Timer pro aktualizaci času každou sekundu
    _timer = Timer.periodic(Duration(seconds: 1), (_) {
      setState(() {
        // Tímto způsobem pravidelně aktualizujeme čas
      });
    });
  }

  // Funkce pro formátování uběhlého času do formátu "mm:ss"
  String _formatElapsedTime(Duration elapsed) {
    int minutes = elapsed.inMinutes;
    int seconds = elapsed.inSeconds % 60;
    return "$minutes:${seconds.toString().padLeft(2, '0')}";
  }

  @override
  void dispose() {
    super.dispose();
    _positionStreamSubscription.cancel();
    _timer?.cancel(); // Zastavení Timeru při zničení widgetu
  }

  @override
  Widget build(BuildContext context) {
    if (_permission == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Navigace - ${widget.selectedMountain}'),
        ),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Navigace - ${widget.selectedMountain}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('Vybraná trasa: ${widget.selectedRoute}'),
            SizedBox(height: 40),
            if (_serviceEnabled &&
                (_permission == LocationPermission.whileInUse ||
                    _permission == LocationPermission.always))
              _currentPosition != null
                  ? Text('Aktuální poloha: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}')
                  : CircularProgressIndicator(),
            if (!_serviceEnabled)
              Text('GPS služba není povolena', style: TextStyle(color: Colors.red)),
            if (_permission == LocationPermission.denied)
              Text('Povolení k poloze je zamítnuto', style: TextStyle(color: Colors.red)),
            Expanded(
              child: FutureBuilder<List<LatLng>>(
                future: widget.selectedPolyline,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError) {
                    return Center(child: Text('Chyba při získávání trasy'));
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(child: Text('Vyberte trasu pro zobrazení'));
                  }

                  final route = snapshot.data!;
                  _startPoint = route.first; // Nastavení počátečního bodu trasy
                  _endPoint = route.last; // Nastavení posledního bodu trasy

                  return FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                      initialZoom: 14.0,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                        subdomains: ['a', 'b', 'c'],
                      ),
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: route,
                            strokeWidth: 4.0,
                            color: Colors.blue,
                          ),
                        ],
                      ),
                      CurrentLocationLayer(
                        followOnLocationUpdate: FollowOnLocationUpdate.always,
                        style: LocationMarkerStyle(
                          marker: const DefaultLocationMarker(
                            child: Icon(
                              Icons.navigation,
                              color: Colors.white,
                            ),
                          ),
                          markerSize: const Size(40, 40),
                          markerDirection: MarkerDirection.heading,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            // Zobrazení tlačítka Start pokud je uživatel blízko startu trasy
            if (_isNearStart && !_isTimerRunning)
              ElevatedButton(
                onPressed: () {
                  // Spustit stopky při stisknutí tlačítka Start
                  print("Start!");
                  _startTimer();
                },
                child: Text("Start"),
              ),
            // Zobrazení času
            if (_isTimerRunning)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'Čas: ${_stopwatch.elapsed.inMinutes}:${(_stopwatch.elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 24),
                ),
              ),
            // Zobrazení uběhlého času po zastavení stopky
            if (!_isTimerRunning && _elapsedTime.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'Uběhlý čas: $_elapsedTime',
                  style: TextStyle(fontSize: 24, color: Colors.green),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
