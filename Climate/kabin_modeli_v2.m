%% kabin_modeli_v2.m
% Gri kutu kabin modeli (PDF Bolum 7):
%   - kovalar (Cr, Cw, Gwr, Gaw) DENKLEMLE; sayilar parametre_bul.m'nin
%     bulduklari (kabin_param.mat). Dosya yoksa eski varsayimlar kullanilir.
%   - isitici kapasitesi dis sicakliga bagli LOOKUP TABLE ile (Saturation Dynamic).
%   - PI kontrolcu acik bloklarla kuruldu; anti-windup = back-calculation
%     (degisken sinirla calisir; PDF denklem 7.2).
% Once parametre_bul.m'yi calistir, sonra bunu. Yalnizca standart Simulink.

clear; clc;
mdl = 'Kabin_v2';
if bdIsLoaded(mdl), close_system(mdl, 0); end
if exist([mdl '.slx'], 'file'), delete([mdl '.slx']); end

param = [ ...
 'if exist(''kabin_param.mat'',''file''), load(''kabin_param.mat'');'   newline ...
 'else, Cr=150; Cw=3000; Gwr=2.5; Gaw=1.0; end'                         newline ...
 'tau_a = 40;          % s   isitici gecikmesi'                           newline ...
 'Kp = 4; Ti = 200; Ki = Kp/Ti;   % PI'                                   newline ...
 'Tt = Ti/2; Kt = 1/Tt;           % anti-windup (back-calculation)'      newline ...
 'Ta_bp   = [-25 -15 -5  5   15  ];  % C   (UYDURMA tablo, ornek)'        newline ...
 'umax_tb = [ 17 20.5 25 28 29.5];   % kW  dis sicakliga gore kapasite'   newline ...
 'r = 22; Ta = -5;'                                                       newline ...
 'Qint0 = 2.1; Qint1 = 4.5; t_yolcu = 5400;'                              newline ...
 'Tr0 = Ta; Tw0 = Ta;             % gece bekledi: her sey dis sicaklikta' newline ];
eval(param);

new_system(mdl); open_system(mdl);
set_param(mdl, 'InitFcn', param);
set_param(mdl, 'StopTime', '10800', 'Solver', 'ode45', 'MaxStep', '5');
set_param(mdl, 'ReturnWorkspaceOutputs', 'on', 'ReturnWorkspaceOutputsName', 'out');

%% 3) Ust seviye bloklar
B = @(lib, name, varargin) add_block(lib, [mdl '/' name], varargin{:});
B('simulink/Sources/Constant', 'Hedef', 'Value', 'r', 'Position', [20 95 60 125]);
B('simulink/Math Operations/Sum', 'Hata', 'Inputs', '|+-', 'IconShape', 'round', 'Position', [100 100 120 120]);
% --- PI (acik hali): v = Kp*e + I,  dI/dt = Ki*e + Kt*(u - v)
B('simulink/Math Operations/Gain', 'P_kazanci', 'Gain', 'Kp', 'Position', [160 60 200 90]);
B('simulink/Math Operations/Gain', 'I_kazanci', 'Gain', 'Ki', 'Position', [160 140 200 170]);
B('simulink/Math Operations/Sum',  'I_girisi',  'Inputs', '++', 'Position', [240 140 260 180]);
B('simulink/Continuous/Integrator','I_birikim', 'InitialCondition', '0', 'Position', [290 145 320 175]);
B('simulink/Math Operations/Sum',  'PI_toplam', 'Inputs', '++', 'Position', [360 80 380 120]);
B('simulink/Discontinuities/Saturation Dynamic', 'Kapasite_siniri', 'Position', [430 70 480 130]);
B('simulink/Sources/Constant', 'Alt_sinir', 'Value', '0', 'Position', [370 150 400 170]);
B('simulink/Lookup Tables/1-D Lookup Table', 'Kapasite_tablosu', ...
    'Table', 'umax_tb', 'BreakpointsForDimension1', 'Ta_bp', 'ExtrapMethod', 'Clip', ...
    'Position', [340 10 400 50]);
B('simulink/Math Operations/Sum',  'Doyum_farki', 'Inputs', '+-', 'Position', [430 200 450 240]);
B('simulink/Math Operations/Gain', 'Kt_kazanci', 'Gain', 'Kt', 'Orientation', 'left', 'Position', [300 205 340 235]);
% --- isitici ve kabin
B('simulink/Continuous/Transfer Fcn', 'Isitici_gecikmesi', 'Numerator', '1', 'Denominator', '[tau_a 1]', 'Position', [520 80 590 120]);
B('simulink/Sources/Constant', 'Dis_sicaklik', 'Value', 'Ta', 'Position', [240 15 280 45]);
B('simulink/Sources/Step', 'Yolcu_yuku', 'Time', 't_yolcu', 'Before', 'Qint0', 'After', 'Qint1', 'Position', [520 230 560 260]);
B('simulink/Ports & Subsystems/Subsystem', 'Kabin', 'Position', [640 75 760 265]);
B('simulink/Signal Routing/Mux', 'Mux', 'Inputs', '2', 'Position', [820 60 825 140]);
B('simulink/Sinks/Scope', 'Sicaklik_ekrani', 'Position', [860 85 900 115]);
B('simulink/Sinks/Scope', 'Isitici_gucu_ekrani', 'Position', [640 10 680 40]);
B('simulink/Sinks/To Workspace', 'Tr_kayit', 'VariableName', 'Tr_log', 'SaveFormat', 'Timeseries', 'Position', [820 180 880 200]);
B('simulink/Sinks/To Workspace', 'q_kayit',  'VariableName', 'q_log',  'SaveFormat', 'Timeseries', 'Position', [720 15 780 35]);

%% 4) Kabin alt sistemini doldur
k = [mdl '/Kabin'];
delete_line(k, 'In1/1', 'Out1/1');      % varsayilan ici bosalt
delete_block([k '/In1']);
delete_block([k '/Out1']);

% Girisler ve cikislar
add_block('simulink/Sources/In1',  [k '/q'],    'Port', '1', 'Position', [20 40 50 54]);
add_block('simulink/Sources/In1',  [k '/Ta'],   'Port', '2', 'Position', [20 250 50 264]);
add_block('simulink/Sources/In1',  [k '/Qint'], 'Port', '3', 'Position', [20 90 50 104]);
add_block('simulink/Sinks/Out1',   [k '/Tr_out'], 'Port', '1', 'Position', [560 63 590 77]);
add_block('simulink/Sinks/Out1',   [k '/Tw_out'], 'Port', '2', 'Position', [560 213 590 227]);

% --- Kabin havasi (kucuk kova): Cr * dTr/dt = Gwr*(Tw-Tr) + q + Qint
add_block('simulink/Math Operations/Sum', [k '/Hava_isi_toplami'], ...
    'Inputs', '+++', 'Position', [200 50 230 90]);
add_block('simulink/Math Operations/Gain', [k '/Hava_kapasitesi'], ...
    'Gain', '1/Cr', 'Position', [280 55 330 85]);
add_block('simulink/Continuous/Integrator', [k '/Tr'], ...
    'InitialCondition', 'Tr0', 'Position', [380 55 410 85]);

% --- Hava ile govde arasindaki boru: Gwr*(Tw-Tr)
add_block('simulink/Math Operations/Sum', [k '/Tw_eksi_Tr'], ...
    'Inputs', '+-', 'Position', [450 135 470 175]);
add_block('simulink/Math Operations/Gain', [k '/Gwr_boru'], ...
    'Gain', 'Gwr', 'Orientation', 'left', 'Position', [370 140 420 170]);

% --- Govde (buyuk kova): Cw * dTw/dt = Gaw*(Ta-Tw) - Gwr*(Tw-Tr)
add_block('simulink/Math Operations/Sum', [k '/Ta_eksi_Tw'], ...
    'Inputs', '+-', 'Position', [100 240 120 280]);
add_block('simulink/Math Operations/Gain', [k '/Gaw_boru'], ...
    'Gain', 'Gaw', 'Position', [150 245 200 275]);
add_block('simulink/Math Operations/Sum', [k '/Govde_isi_toplami'], ...
    'Inputs', '+-', 'Position', [250 200 280 240]);
add_block('simulink/Math Operations/Gain', [k '/Govde_kapasitesi'], ...
    'Gain', '1/Cw', 'Position', [320 205 370 235]);
add_block('simulink/Continuous/Integrator', [k '/Tw'], ...
    'InitialCondition', 'Tw0', 'Position', [420 205 450 235]);

% Kabin icindeki baglantilar
L = @(a,b) add_line(k, a, b, 'autorouting', 'on');
L('q/1',               'Hava_isi_toplami/2');
L('Qint/1',            'Hava_isi_toplami/3');
L('Gwr_boru/1',        'Hava_isi_toplami/1');
L('Hava_isi_toplami/1','Hava_kapasitesi/1');
L('Hava_kapasitesi/1', 'Tr/1');
L('Tr/1',              'Tr_out/1');
L('Tw/1',              'Tw_eksi_Tr/1');
L('Tr/1',              'Tw_eksi_Tr/2');
L('Tw_eksi_Tr/1',      'Gwr_boru/1');
L('Ta/1',              'Ta_eksi_Tw/1');
L('Tw/1',              'Ta_eksi_Tw/2');
L('Ta_eksi_Tw/1',      'Gaw_boru/1');
L('Gaw_boru/1',        'Govde_isi_toplami/1');
L('Gwr_boru/1',        'Govde_isi_toplami/2');
L('Govde_isi_toplami/1','Govde_kapasitesi/1');
L('Govde_kapasitesi/1','Tw/1');
L('Tw/1',              'Tw_out/1');

%% 5) Ust seviye baglantilar
M = @(a,b) add_line(mdl, a, b, 'autorouting', 'on');
M('Hedef/1',            'Hata/1');
M('Hata/1',             'P_kazanci/1');
M('Hata/1',             'I_kazanci/1');
M('I_kazanci/1',        'I_girisi/1');
M('Kt_kazanci/1',       'I_girisi/2');
M('I_girisi/1',         'I_birikim/1');
M('P_kazanci/1',        'PI_toplam/1');
M('I_birikim/1',        'PI_toplam/2');
M('Kapasite_tablosu/1', 'Kapasite_siniri/1');   % up
M('PI_toplam/1',        'Kapasite_siniri/2');   % u
M('Alt_sinir/1',        'Kapasite_siniri/3');   % lo
M('Kapasite_siniri/1',  'Doyum_farki/1');       % u (sinirlanmis)
M('PI_toplam/1',        'Doyum_farki/2');       % v (sinirsiz)
M('Doyum_farki/1',      'Kt_kazanci/1');
M('Dis_sicaklik/1',     'Kapasite_tablosu/1');
M('Kapasite_siniri/1',  'Isitici_gecikmesi/1');
M('Isitici_gecikmesi/1','Kabin/1');
M('Dis_sicaklik/1',     'Kabin/2');
M('Yolcu_yuku/1',       'Kabin/3');
M('Kabin/1',            'Hata/2');
M('Hedef/1',            'Mux/1');
M('Kabin/1',            'Mux/2');
M('Mux/1',              'Sicaklik_ekrani/1');
M('Kabin/1',            'Tr_kayit/1');
M('Isitici_gecikmesi/1','Isitici_gucu_ekrani/1');
M('Isitici_gecikmesi/1','q_kayit/1');

%% 6) Kaydet, calistir, kontrol et
save_system(mdl);
out = sim(mdl);
Tr = out.get('Tr_log');  q = out.get('q_log');
fprintf('Parametreler: Cr=%.1f Cw=%.0f Gwr=%.3f Gaw=%.3f\n', Cr, Cw, Gwr, Gaw);
fprintf('Ta = %g C icin kapasite siniri = %.2f kW\n', Ta, interp1(Ta_bp, umax_tb, Ta));
for m = [10 30 60 89 120 180]
    fprintf('t = %3d dk : Tr = %6.2f C   q = %6.2f kW\n', m, deger(Tr,m*60), deger(q,m*60));
end
fprintf('en yuksek Tr = %.2f C\n', max(Tr.Data));

figure('Name','Kabin_v2');
subplot(2,1,1); plot(Tr.Time/60, squeeze(Tr.Data), 'b'); yline(r,'k--'); grid on; ylabel('T_r [C]');
subplot(2,1,2); plot(q.Time/60, squeeze(q.Data), 'r'); grid on; ylabel('q [kW]'); xlabel('zaman [dk]');

function y = deger(ts, t)
    [tt, i] = unique(ts.Time);
    d = squeeze(ts.Data);
    y = interp1(tt, d(i), t);
end
