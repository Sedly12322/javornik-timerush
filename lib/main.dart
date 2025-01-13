import 'dart:async';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:wakelock_plus/wakelock_plus.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Ujistíme se, že inicializace Firebase probíhá před spuštěním aplikace
  await Firebase.initializeApp(); // Inicializace Firebase
  await initializeDateFormatting('cs_CZ', null); // Inicializace pro českou lokalitu
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
  bool _isLoginMode = true; // Přidáme tuto proměnnou pro určení, zda jsme v režimu přihlášení nebo registrace

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
        height: 1300,
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
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(
                            0xFF8EE9CD),width: 3)),
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
                          focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Color(
                              0xFF7AECBC),width: 3)),
                        ),
                      ),
                    SizedBox(height: 20),
                    // Zobrazí pole pro heslo v obou režimech
                    TextField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Heslo',
                        border: OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(
                            0xFF6AEEAE),width: 3)),
                      ),
                      obscureText: true,
                    ),
                    SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _isLoginMode ? _login : _register, // Podmíněné volání funkce
                      child: Text(_isLoginMode ? 'Přihlásit se' : 'Registrovat se'), // Dynamický text
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        foregroundColor: Colors.black,
                        textStyle: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold
                        )
                      ),
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
                          : 'Máte účet? Přihlaste se',
                          style: TextStyle(
                          color: Colors.black
                      ),
                      ),
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

extension StringCasingExtension on String {
  String capitalize() {
    if (this == null || this.isEmpty) {
      return this;
    }
    return this[0].toUpperCase() + this.substring(1);
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
  String _weatherIconUrl = "";  // URL pro ikonu počasí
  String _currentTemperature = "";  // Aktuální teplota
  String _weatherDescription = "";  // Popis počasí

  @override
  void initState() {
    super.initState();
    _loadMountains();  // Načítání hor z Firestore
    _loadUsername();
    _fetchWeather();
    WakelockPlus.enable();
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
    if (_selectedRoute == null) {
      // Pokud není vybraná trasa, zobrazí se Snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vyberte trasu před navigací')),
      );
    } else {
      // Pokud je vybraná trasa, navigujeme
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
  }
  void _navigateToLeaderboard() {
    if (_selectedMountain != null && _selectedRoute != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LeaderboardScreen(
            selectedMountain: _selectedMountain!,
            selectedRoute: _selectedRoute!,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vyberte horu a trasu před zobrazením žebříčku')),
      );
    }
  }

  Future<void> _fetchWeather() async {
    final apiKey = "f8b639faa2109c23051daa0a4b532182";  // Ujistěte se, že máte správný API klíč
    final latitude = 50.0755;  // Příklad: zeměpisná šířka
    final longitude = 14.4378;  // Příklad: zeměpisná délka

    final response = await http.get(Uri.parse(
        'https://api.openweathermap.org/data/2.5/weather?lat=$latitude&lon=$longitude&appid=$apiKey&units=metric'
    ));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final weather = data['weather'][0]; // Získání informací o počasí
      final main = data['main']; // Získání údajů o teplotě
      final wind = data['wind']; // Získání údajů o větru

      setState(() {
        _weatherIconUrl = "http://openweathermap.org/img/wn/${weather['icon']}@2x.png";
        _currentTemperature = "${main['temp']}°C";  // Teplota v °C
        _weatherDescription = weather['description'];  // Popis počasí

        // Formátovaný text pro "Feels like" a vítr
        String feelsLike = "Feels like ${main['feels_like']}°C";
        String windSpeed = "Wind: ${wind['speed']} m/s";

        _weatherDescription = "$feelsLike. ${_weatherDescription.capitalize()}. $windSpeed";
      });
    } else {
      setState(() {
        _weatherIconUrl = "";  // V případě chyby, ikona nebude
        _currentTemperature = "Chyba při načítání počasí";
        _weatherDescription = "";  // Popis počasí
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Mapa s výběrem destinace"),
        backgroundColor: Color.fromRGBO(200, 228, 255, 1),
        actions: [
          IconButton(
            icon: Icon(Icons.leaderboard),
            onPressed: _navigateToLeaderboard,
          ),
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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color.fromRGBO(200, 228, 255, 1), Color(0xFF58AEFD)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Ikona počasí vlevo
                if (_weatherIconUrl.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 40.0, right: 8.0),
                    child: Image.network(
                      _weatherIconUrl,
                      width: 80,
                      height: 80,
                    ),
                  ),
                // Text "Ahoj, [username]" v bílém zaobleném rámečku (pravý okraj)
                Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: Container(
                    width: 200,
                    height: 60,
                    padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20.0),
                    ),
                    child: Center(
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(fontSize: 24, color: Colors.black),
                          children: [
                            TextSpan(
                              text: 'Ahoj, ',
                              style: TextStyle(fontWeight: FontWeight.normal),
                            ),
                            TextSpan(
                              text: '$_username!',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20.0),
                  child: FutureBuilder<List<LatLng>>(
                    future: _getRouteForSelectedRoute(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Center(child: CircularProgressIndicator());
                      } else if (snapshot.hasError) {
                        return Center(child: Text('Chyba při získávání trasy'));
                      } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return Container(
                          decoration: BoxDecoration(
                            color: Color(0xFFCFFDF2),
                            borderRadius: BorderRadius.circular(20.0),
                          ),
                          child: Center(
                            child: Text(
                              'Vyberte trasu pro zobrazení',
                              style: TextStyle(fontSize: 18),
                            ),
                          ),
                        );
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
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Řádek s DropdownButton pro výběr hory a trasy
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Rámeček pro výběr hory
                      Expanded(
                        child: Container(
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8.0), // Zaoblené rohy
                          ),
                          child: Center(
                            child: DropdownButton<String>(
                              underline: SizedBox.shrink(),
                              alignment: Alignment.center,
                              value: _selectedMountain,
                              style: TextStyle(fontSize: 15, color: Colors.black),
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
                                  _selectedRoute = null; // Resetuje vybranou trasu
                                  _loadRoutesForSelectedMountain();
                                });
                              },
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 10),
                      // Rámeček pro výběr trasy
                      Expanded(
                        child: Container(
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8.0), // Zaoblené rohy
                          ),
                          child: Center(
                            child: DropdownButton<String>(
                              underline: SizedBox.shrink(),
                              alignment: Alignment.center,
                              icon: null,
                              value: _selectedRoute,
                              hint: Text('Vyberte trasu'),
                              style: TextStyle(fontSize: 15, color: Colors.black),
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
                        ),
                      ),
                    ],
                  ),

                  // Mezera mezi dropdowny a počasím
                  SizedBox(height: 16.0),

                  // Row pro teplotu a popis počasí
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start, // Pro zarovnání vertikálně nahoru
                    children: [
                      // Container pro zobrazení teploty
                      if (_currentTemperature.isNotEmpty)
                        Container(
                          padding: EdgeInsets.only(left: 8, right: 8),
                          width: 120,
                          height: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8.0),
                            color: Colors.white,
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center, // Vertikálně na střed
                              crossAxisAlignment: CrossAxisAlignment.center, // Horizontálně na střed
                              children: [
                                Text(
                                  _currentTemperature,
                                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),

                      SizedBox(width: 16), // Mezera mezi kontejnery pro počasí

                      // Column pro popis počasí a tlačítko navigace, zarovnáno vpravo
                      if (_currentTemperature.isNotEmpty)
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight, // Zarovnání vpravo
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Container pro popis počasí
                                Container(
                                    padding: EdgeInsets.only(left: 8, right: 8),
                                    height: 40,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8.0),
                                      color: Colors.white,
                                    ),
                                    child: Center(
                                      child: Text(
                                        _weatherDescription,
                                        style: TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                    ),
                                  ),

                                SizedBox(height: 8), // Mezera mezi popisem počasí a tlačítkem

                                // Tlačítko pro navigaci
                                ElevatedButton(
                                  onPressed: _navigateToNavigationScreen,
                                  child: Text("Navigovat"),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
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

  Future<void> enableBackgroundExecution() async {
    const androidConfig = FlutterBackgroundAndroidConfig(
      notificationTitle: "Background Service",
      notificationText: "Measuring time in the background",
      notificationImportance: AndroidNotificationImportance.normal,
    );

    bool hasPermission = await FlutterBackground.hasPermissions;
    if (!hasPermission) {
      hasPermission = await FlutterBackground.initialize(androidConfig: androidConfig);
    }

    if (hasPermission) {
      await FlutterBackground.enableBackgroundExecution();
    }
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
                  enableBackgroundExecution();
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




class LeaderboardScreen extends StatelessWidget {
  final String selectedMountain;
  final String selectedRoute;

  LeaderboardScreen({
    required this.selectedMountain,
    required this.selectedRoute,
  });

  int _timeStringToSeconds(String timeString) {
    final parts = timeString.split(':');
    if (parts.length != 3) {
      throw FormatException("Neplatný formát času: $timeString");
    }
    final hours = int.parse(parts[0]);
    final minutes = int.parse(parts[1]);
    final seconds = int.parse(parts[2]);
    return (hours * 3600) + (minutes * 60) + seconds;
  }

  Future<List<Map<String, dynamic>>> _fetchLeaderboard() async {
    final List<Map<String, dynamic>> leaderboard = [];

    try {
      // Načítání všech uživatelů
      final usersSnapshot = await FirebaseFirestore.instance.collection('users').get();

      for (var userDoc in usersSnapshot.docs) {
        // Načítání výšlapů uživatele podle názvu hory a názvu trasy
        final climbsSnapshot = await userDoc.reference
            .collection('climbs')
            .where('mountainID', isEqualTo: selectedMountain)
            .where('trailID', isEqualTo: selectedRoute)
            .get();

        for (var climbDoc in climbsSnapshot.docs) {
          Timestamp timestamp = climbDoc['date']; // Datum jako Timestamp
          DateTime date = timestamp.toDate(); // Převede na DateTime
          String formattedDate = DateFormat('d. MMMM yyyy, HH:mm', 'cs_CZ').format(date); // Naformátuje s časem

          leaderboard.add({
            'username': userDoc['username'],
            'time': climbDoc['time'], // Čas jako řetězec
            'date': formattedDate,    // Přidáme formátované datum
          });
        }
      }

      // Seřazení výsledků podle času převedeného na sekundy
      leaderboard.sort((a, b) {
        int timeA = _timeStringToSeconds(a['time']);
        int timeB = _timeStringToSeconds(b['time']);
        return timeA.compareTo(timeB);
      });
    } catch (e) {
      print('Chyba při načítání žebříčku: $e');
    }

    return leaderboard;
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Žebříček - $selectedRoute'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _fetchLeaderboard(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Chyba při načítání žebříčku'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(child: Text('Žádné záznamy pro tuto trasu'));
          }

          final leaderboard = snapshot.data!;
          return ListView.builder(
            itemCount: leaderboard.length,
            itemBuilder: (context, index) {
              final entry = leaderboard[index];
              return ListTile(
                leading: Text('#${index + 1}'),
                title: Text(entry['username']),
                subtitle: Text(entry['date']), // Zobrazení datumu a času
                trailing: Text(entry['time']), // Čas jako "hh:mm:ss"
              );
            },
          );
        },
      ),
    );
  }
}

