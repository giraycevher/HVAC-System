%% BUS_HVAC_PARAMS  All parameters of the bus_hvac model, in one place.
%  Run this file once, or just run build_bus_hvac / run_scenarios (they call it).
%  All values are generic textbook-level assumptions for a 12 m electric coach.
%  They do not describe any specific vehicle. Replace them with your own data.
%  This file does not clear the workspace.

%% --- SCENARIO INPUTS (change these, or let run_scenarios.m change them)
T_set       = 22;         % cabin temperature setpoint [degC]
T_out_time  = [0 7200];   % outdoor temperature profile: time points [s]
T_out_val   = [-10 -10];  % outdoor temperature profile: values [degC]
T_cab0      = -10;        % initial cabin temperature [degC]
T_w0        = -10;        % initial water temperature [degC]
n_pass      = 20;         % number of passengers [-]
Q_solar     = 0;          % solar gain into the cabin [W]
hp_enable   = 1;          % 1 = roof heat pump available, 0 = not available
fuel_enable = 0;          % 1 = fuel-fired auxiliary heater allowed, 0 = not allowed
front_fan   = 1;          % 1 = front box (driver/defrost) blower running

%% --- FLUID PROPERTIES
c_w     = 3600;  % specific heat of water-glycol 50/50 [J/(kg K)]
cp_air  = 1005;  % specific heat of air [J/(kg K)]
rho_air = 1.2;   % air density [kg/m^3]

%% --- CABIN (one lumped air node)
V_cab           = 60;                                    % cabin air volume [m^3]
cab_mass_factor = 5;                                     % effective thermal mass / air mass (seats, panels, luggage racks) [-]
C_cab           = cab_mass_factor*rho_air*V_cab*cp_air;  % cabin heat capacity [J/K]
A_wall          = 120;                                   % insulated body area [m^2]
U_wall          = 1.2;                                   % body U-value [W/(m^2 K)]
A_glass         = 28;                                    % glazing area [m^2]
U_glass         = 2.8;                                   % glazing U-value [W/(m^2 K)]
UA_cab          = U_wall*A_wall + U_glass*A_glass;       % cabin heat loss coefficient [W/K]
m_fresh         = 0.10;                                  % fresh air mass flow [kg/s]
q_pass          = 75;                                    % sensible heat per passenger [W]

%% --- ROOF HEAT PUMP (acts directly on cabin air)
hp_T       = [-20 -10 0 10 20];               % outdoor temperature grid [degC]
hp_Qheat   = [8000 12000 16000 18000 18000];  % heating capacity at full load [W]
hp_COP     = [1.6 2.0 2.6 3.2 3.6];           % heating COP [-]
Q_cool_max = 20000;                           % cooling capacity at full load [W]
EER        = 2.5;                             % cooling efficiency (cooling power / electric power) [-]

%% --- ELECTRIC WATER HEATER
P_heater_max      = 20000;        % rated power [W]
der_T             = [-40 55 90];  % water temperature grid for derating [degC]
der_f             = [1 1 0.6];    % available power fraction [-]
T_heater_cut      = 88;           % internal over-temperature cut-out [degC]
T_heater_cut_hyst = 10;           % cut-out hysteresis [K]
m_flow_min        = 0.05;         % minimum water flow for heater operation [kg/s]

%% --- FUEL-FIRED AUXILIARY HEATER (optional)
P_fuel_max     = 30000;  % heat output [W]
T_fuel_on      = 65;     % burner starts below this water temperature [degC]
T_fuel_off     = 78;     % burner stops above this water temperature [degC]
T_fuel_cut     = 85;     % device thermostat [degC]
t_fuel_ignite  = 60;     % ignition delay [s]
tau_fuel       = 60;     % time constant of heat output build-up [s]
T_fuel_out_max = 5;      % burner is only allowed below this outdoor temperature [degC]

%% --- WATER CIRCUIT (lumped, well-mixed nodes)
M_aux         = 8;             % water mass: return collector + pump + fuel heater [kg]
M_heater      = 3;             % water mass: electric heater [kg]
M_conv        = 20;            % water mass: side-wall convectors [kg]
M_fsup        = 4;             % water mass: supply pipe to the front box [kg]
M_fhx         = 1.5;           % water mass: front box heat exchanger [kg]
M_fret        = 4;             % water mass: return pipe from the front box [kg]
UA_conv_stage = [30 130 220];  % convector UA at fan stage 0 / 1 / 2 [W/K]
eps_front     = 0.7;           % front box heat exchanger effectiveness [-]
m_air_front   = 0.25;          % front box air mass flow [kg/s]
P_pump        = 150;           % circulation pump electric power [W]

%% --- HYDRAULICS  dp = K * mdot^2  (K in Pa/(kg/s)^2)
dp0       = 100e3;                                                   % pump head at zero flow [Pa]
b_pump    = 8e4;                                                     % pump curve coefficient: dp = dp0 - b_pump*mdot^2
K_src     = 9e4;                                                     % resistance of the common part (heaters, collector)
K_valve   = 1.5e5;                                                   % resistance of a fully open control valve
K_conv    = 1.2e5;                                                   % resistance of the convector branch
K_front   = 2.5e5;                                                   % resistance of the front box branch
K_byp     = 1.5e6;                                                   % resistance of the permanent bypass
valve_min = 0.05;                                                    % leakage opening of a closed valve [-]
h_grid    = linspace(valve_min, 1, 20);                              % valve opening grid
Gc_tab    = 1./sqrt(K_conv + K_valve./h_grid.^2);                    % convector branch conductance G = 1/sqrt(K)
Gf_tab    = 1./sqrt(K_front + K_valve./h_grid.^2);                   % front box branch conductance
G_byp     = 1/sqrt(K_byp);                                           % bypass conductance
G_grid    = linspace(G_byp, Gc_tab(end) + Gf_tab(end) + G_byp, 30);  % total parallel conductance grid
mtot_tab  = sqrt(dp0./(b_pump + K_src + 1./G_grid.^2));              % total flow at the operating point [kg/s]

%% --- CONTROL: mode supervisor
Ts_mode     = 5;     % decision period [s]
e_heat_on   = 0.3;   % heating on when e = T_set - T_cab >= this [K]
e_heat_off  = -0.5;  % heating off when e <= this [K]
e_cool_on   = 0.5;   % cooling on when -e >= this [K]
e_cool_off  = -0.3;  % cooling off when -e <= this [K]
T_heat_lock = 18;    % no heating above this outdoor temperature [degC] (2 K hysteresis)
T_cool_lock = 12;    % no cooling below this outdoor temperature [degC] (2 K hysteresis)
t_dwell     = 300;   % minimum ventilation time between heating and cooling [s]

%% --- CONTROL: cabin temperature (split range u = -1 ... 2)
Kp_cab     = 0.6;    % PI proportional gain [1/K]
Ki_cab     = 0.004;  % PI integral gain [1/(K s)]
T_conv_max = 65;     % convector water setpoint at full demand [degC]

%% --- CONTROL: convectors
d_on       = 0.02;    % convector circuit is used above this demand [-]
Kp_v       = 0.08;    % valve PI proportional gain [1/K]
Ki_v       = 0.0015;  % valve PI integral gain [1/(K s)]
d_fan1_on  = 0.05;    % fan stage 1 on above this demand [-]
d_fan1_off = 0.02;    % fan stage 1 off below this demand [-]
d_fan2_on  = 0.9;     % fan stage 2 on above this demand [-]
d_fan2_off = 0.3;     % fan stage 2 off below this demand [-]
T_fan_on   = 40;      % fans released above this convector water temperature [degC]
T_fan_off  = 35;      % fans blocked below this convector water temperature [degC]

%% --- CONTROL: front box
blow_T       = [-20 0 10 18];  % outdoor temperature grid [degC]
blow_set     = [42 38 28 22];  % blow-out temperature setpoint [degC]
Kp_f         = 0.05;           % valve PI proportional gain [1/K]
Ki_f         = 0.002;          % valve PI integral gain [1/(K s)]
front_margin = 15;             % water must be this much hotter than the blow-out setpoint [K]

%% --- CONTROL: supply water and heaters
mar_T          = [-20 0 15];  % outdoor temperature grid [degC]
mar            = [15 10 5];   % supply margin above the highest request [K]
T_sup_max      = 85;          % maximum supply water setpoint [degC]
e_heater_on    = 2;           % heater enabled when setpoint - supply >= this [K]
e_heater_off   = -8;          % heater disabled when setpoint - supply <= this [K]
t_heater_delay = 10;          % pump runs this long before the heater starts [s]
Kp_h           = 0.08;        % heater PI proportional gain [1/K]
Ki_h           = 0.002;       % heater PI integral gain [1/(K s)]
t_pump_run     = 60;          % pump after-run [s]
