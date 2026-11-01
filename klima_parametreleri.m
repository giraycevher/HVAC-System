%% klima_parametreleri.m
% eCoach otobüs klimasi (sogutma) Simulink modeli - tum parametreler.
% Bu dosya modelin InitFcn callback'inden her Run oncesi otomatik calisir.
% Sicakliklar degC, gucler W, entalpiler J/kg, kutle debileri kg/s.

%% 1) Senaryo: gunes altinda beklemis otobus (hot soak) + yaz gunu
T_amb      = 35;       % dis hava sicakligi [degC]
Q_solar    = 6000;     % gunes yuku (camlardan gelen) [W]
N_pass     = 40;       % yolcu sayisi [-]
q_pass     = 100;      % yolcu basina duyulur isi [W]
T_set      = 24;       % kabin hedef sicakligi [degC]
t_on       = 10;       % klimanin acildigi an [s]
T_cab0     = 45;       % baslangic kabin havasi [degC]
T_yapi0    = 45;       % baslangic ic yapi (koltuk, panel) [degC]
t_stop     = 3600;     % simulasyon suresi [s]

%% 2) Kabin (isitma modeliyle ayni degerler)
C_air      = 5e5;      % kabin havasi isil kapasitesi [J/K]
C_yapi     = 5e6;      % ic yapi isil kapasitesi [J/K]
UA_amb     = 1200;     % kabin - dis ortam isi gecis katsayisi [W/K]
UA_as      = 800;      % hava - ic yapi isi gecis katsayisi [W/K]

%% 3) Hava tarafi (cati klima unitesi)
cp_air     = 1006;     % havanin ozgul isisi [J/(kg K)]
m_air_e    = 2.5;      % evaporator hava debisi [kg/s] (~7500 m3/h)
f_fresh    = 0.2;      % taze hava orani [-] (0 = tam resirkulasyon)
UA_e       = 3600;     % evaporator UA [W/K]
m_air_c    = 5.5;      % kondenser hava debisi [kg/s]
UA_c       = 6500;     % kondenser UA [W/K]

%% 4) Sogutucu cevrim (R134a)
V_d        = 220e-6;   % kompresor stroke hacmi [m3/devir] (220 cm3)
N_max      = 6000;     % kompresor maksimum devri [rpm]
eta_v      = 0.85;     % hacimsel verim [-]
eta_C      = 0.50;     % Carnot verim orani [-]
COP_max    = 10;       % COP ust siniri [-]
dT_min     = 5;        % COP hesabinda minimum (Tc - Te) [K]
C_e        = 30e3;     % evaporator isil kapasitesi (metal + sogutucu) [J/K]
C_c        = 40e3;     % kondenser isil kapasitesi [J/K]

%% 5) Kontrol
Kp         = 0.25;     % PI oransal kazanc [1/K]
Ki         = 0.004;    % PI integral kazanc [1/(K s)]
n_min      = 0.25;     % kompresor minimum hizi [-]
relay_on   = 0.5;      % kompresor ON: hata >= +0,5 K
relay_off  = -1.0;     % kompresor OFF: hata <= -1,0 K
rate_n     = 0.1;      % kompresor hiz degisimi siniri [1/s]
tau_sens   = 15;       % kabin sensoru zaman sabiti [s]
Te_freeze  = 0;        % donma korumasi baslangici [degC]
K_freeze   = 0.25;     % donma korumasi egimi [1/K]
Tc_trip    = 65;       % yuksek basinc kesme (~19 bar) [degC]
Tc_reset   = 55;       % yuksek basinc geri alma [degC]

%% 6) Fan gucleri (enerji hesabi icin)
P_blower   = 1500;     % evaporator fanlari [W]
P_condfan  = 1500;     % kondenser fanlari [W]

%% 7) Turetilmis buyuklukler (elle degistirme)
eps_e = 1 - exp(-UA_e/(m_air_e*cp_air));   % evaporator hava tarafi etkinligi [-]
eps_c = 1 - exp(-UA_c/(m_air_c*cp_air));   % kondenser hava tarafi etkinligi [-]
Vdot_max = eta_v*V_d*N_max/60;             % maksimum emme hacim debisi [m3/s]

%% 8) R134a doyma tablosu (yaklasik; IIR referansi: hf = 200 kJ/kg @ 0 degC)
% Sicaklik noktalari [degC]
T_tab    = [-20   -10     0    10    20    30    40    50    60    70];
% Doyma basinci [bar]
p_tab    = [1.33  2.01  2.93  4.15  5.72  7.70 10.17 13.18 16.82 21.17];
% Doymus buhar yogunlugu [kg/m3]
rhog_tab = [6.78 10.04 14.43 20.23 27.78 37.54 50.09 66.27 87.38 115.6];
% Doymus sivi entalpisi [J/kg]  (kJ/kg * 1e3)
hf_tab   = [173.6 186.7 200.0 213.6 227.5 241.7 256.4 271.6 287.5 304.3]*1e3;
% Doymus buhar entalpisi [J/kg] (kJ/kg * 1e3)
hg_tab   = [386.6 392.7 398.6 404.3 409.8 414.8 419.4 423.4 426.6 428.6]*1e3;

fprintf('klima_parametreleri yuklendi: eps_e = %.3f, eps_c = %.3f\n', eps_e, eps_c);
