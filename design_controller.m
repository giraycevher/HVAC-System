%% DESIGN_CONTROLLER  Optional: check the cabin PI gains with the Control System Toolbox.
%  The cabin with the heat pump as actuator is a first-order system:
%
%     C_cab * dT/dt = u * Q_hp - UA_tot * (T - T_out)
%     G(s) = T(s) / u(s) = K / (tau*s + 1),   K = Q_hp / UA_tot,   tau = C_cab / UA_tot
%
%  The script compares the gains in bus_hvac_params.m with the result of pidtune.
%  It only analyses; it changes nothing in the model.

if isempty(ver('control'))
    error('This script needs the Control System Toolbox. The Simulink model itself does not.');
end
bus_hvac_params;
T_design = -10;                                        % outdoor temperature of the design point [degC]
Q_hp   = interp1(hp_T, hp_Qheat, T_design);            % heat pump capacity there [W]
UA_tot = UA_cab + m_fresh*cp_air;                      % walls + fresh air [W/K]
K      = Q_hp / UA_tot;                                % [K per unit command]
tau    = C_cab / UA_tot;                               % [s]
G      = tf(K, [tau 1]);

C_file = pid(Kp_cab, Ki_cab);                          % gains used in the model
C_auto = pidtune(G, 'PI');                             % toolbox proposal

fprintf('Plant: K = %.1f K, tau = %.0f s\n', K, tau);
fprintf('Model gains  : Kp = %.3f, Ki = %.4f\n', Kp_cab, Ki_cab);
fprintf('pidtune gains: Kp = %.3f, Ki = %.4f\n', C_auto.Kp, C_auto.Ki);
[~, pm_file] = margin(C_file*G);
[~, pm_auto] = margin(C_auto*G);
fprintf('Phase margin : model %.0f deg, pidtune %.0f deg\n', pm_file, pm_auto);

figure('Name', 'Cabin loop', 'Color', 'w');
step(feedback(C_file*G, 1), feedback(C_auto*G, 1), 1800);
grid on;
legend('gains in bus\_hvac\_params', 'pidtune', 'Location', 'southeast');
title('Cabin temperature: response to a 1 K setpoint step (linear model, no saturation)');
