%% parametre_bul.m
% Test verisinden kabin modelinin 4 parametresini bulur:
%   theta = [Cr Cw Gwr Gaw]   (kJ/K, kJ/K, kW/K, kW/K)
% Yontem: cikis hatasi (output-error) + Levenberg-Marquardt (PDF Bolum 5).
% Hicbir toolbox GEREKMEZ (yalnizca temel MATLAB: readmatrix, expm).
%
% Girdi dosyasi (CSV, ilk satir baslik), kolonlar:
%   t_s, Ta_C, Qint_kW, q_kW, Tr_C
%   - t_s  : zaman [s], esit aralikli (ornekleme Ts)
%   - q_kW : kabine giren olculen isitma gucu (su tarafi: m*cp*dT)
%   - Tr_C : olculen kabin hava sicakligi
% Varsayim: test, arac saatlerce bekletildikten sonra baslar
%           (baslangicta govde sicakligi = kabin sicakligi). PDF Bolum 6.
%
% Cikti: kabin_param.mat  (kabin_modeli_v2.m bunu okur)

clear; clc;
dosya = 'test_verisi_ornek.csv';
D = readmatrix(dosya);
t = D(:,1); Ta = D(:,2); Qint = D(:,3); q = D(:,4); Trm = D(:,5);
Ts = t(2) - t(1);
N  = numel(t);

% Veriyi ikiye bol: ilk 4 saat kestirim, kalan dogrulama
nE  = find(t < 4*3600, 1, 'last');
iE  = 1:nE;
iV  = nE+1:N;
fprintf('Ts = %g s, toplam %d ornek; kestirim %d, dogrulama %d\n', Ts, N, nE, numel(iV));

% Baslangic tahmini (eski varsayim). Logaritma ile calisiyoruz: p = ln(theta)
th0 = [150 3000 2.5 1.0];
p   = log(th0(:));

res = @(p) simTr(exp(p), q(iE), Ta(iE), Qint(iE), Trm(1), Ts) - Trm(iE);

%% Levenberg-Marquardt dongusu (PDF denklem 5.6)
mu = 1e-2;
fprintf('\n it      Cr        Cw       Gwr      Gaw     S=sum(r^2)\n');
for it = 1:50
    r = res(p);
    J = jacobian(res, p, r);
    A = J'*J;  g = J'*r;
    dp = -(A + mu*diag(diag(A))) \ g;
    S0 = r'*r;
    r1 = res(p + dp);  S1 = r1'*r1;
    th = exp(p);
    fprintf('%3d %9.2f %9.1f %8.4f %8.4f %12.4f\n', it-1, th, S0);
    if S1 < S0
        p = p + dp;  mu = mu/3;      % iyi adim: kabul et, Gauss-Newton'a yaklas
    else
        mu = mu*3;                   % kotu adim: reddet, daha kucuk/egimli adim
    end
    if norm(dp) < 1e-7, break; end
end
theta = exp(p);

%% Belirsizlik (PDF denklem 5.9): cov(p) = s^2 (J'J)^-1
r  = res(p);  J = jacobian(res, p, r);
s2 = (r'*r) / (nE - 4);
C  = s2 * inv(J'*J);                %#ok<MINV>
relstd = 100*sqrt(diag(C));          % ln-parametrede std = bagil std
R  = C ./ sqrt(diag(C)*diag(C)');    % korelasyon matrisi

ad = {'Cr [kJ/K]','Cw [kJ/K]','Gwr [kW/K]','Gaw [kW/K]'};
fprintf('\n--- SONUC ---\n');
for i = 1:4
    fprintf('%-11s = %9.3f   (+/- %4.1f %%)\n', ad{i}, theta(i), relstd(i));
end
fprintf('artik std s = %.3f K\n', sqrt(s2));
disp('Parametre korelasyonlari:'); disp(round(R,2));

%% Dogrulama: tum veriyi simule et, yalnizca dogrulama kismina bak
y_new = simTr(theta, q, Ta, Qint, Trm(1), Ts);
y_old = simTr(th0,   q, Ta, Qint, Trm(1), Ts);
fitp  = @(y,yh) 100*(1 - norm(y-yh)/norm(y-mean(y)));
fprintf('\nDogrulama fit%%  : yeni %.1f   eski %.1f\n', fitp(Trm(iV),y_new(iV)), fitp(Trm(iV),y_old(iV)));
fprintf('Dogrulama RMSE : yeni %.3f K  eski %.3f K\n', ...
    sqrt(mean((Trm(iV)-y_new(iV)).^2)), sqrt(mean((Trm(iV)-y_old(iV)).^2)));

% Turetilen buyuklukler
Gs = theta(3)*theta(4)/(theta(3)+theta(4));
Am = [-theta(3)/theta(1), theta(3)/theta(1); theta(3)/theta(2), -(theta(3)+theta(4))/theta(2)];
tau = sort(-1./eig(Am));
fprintf('Gs = %.4f kW/K,  zaman sabitleri = %.1f s ve %.1f s\n', Gs, tau);

%% Grafik
figure('Name','Parametre kestirimi');
subplot(2,1,1);
plot(t/3600, Trm, 'Color',[.7 .7 .7]); hold on;
plot(t/3600, y_old, '--', 'Color',[.85 .37 .01]);
plot(t/3600, y_new, 'b', 'LineWidth', 1);
xline(t(nE)/3600, 'k'); grid on; ylabel('T_r [C]');
legend('olcum','eski varsayim','tanimlanan model','Location','southeast');
subplot(2,1,2);
plot(t/3600, Trm - y_new, 'b'); xline(t(nE)/3600,'k'); grid on;
ylabel('artik [K]'); xlabel('zaman [saat]');

%% Kaydet
Cr = theta(1); Cw = theta(2); Gwr = theta(3); Gaw = theta(4);
save('kabin_param.mat', 'Cr', 'Cw', 'Gwr', 'Gaw');
fprintf('\nkabin_param.mat kaydedildi.\n');

%% ------------------------------------------------------------------
function y = simTr(th, q, Ta, Qint, T0, Ts)
% Iki kovali modeli ZOH ile TAM ayriklastirip simule eder (PDF Bolum 5.1).
% Girisler ornekler arasinda sabit kabul edilir.
    Cr = th(1); Cw = th(2); Gwr = th(3); Gaw = th(4);
    A = [-Gwr/Cr,  Gwr/Cr;
          Gwr/Cw, -(Gwr+Gaw)/Cw];
    B = [1/Cr, 0,      1/Cr;        % girisler: [q, Ta, Qint]
         0,    Gaw/Cw, 0   ];
    M = zeros(5);  M(1:2,1:2) = A*Ts;  M(1:2,3:5) = B*Ts;
    E = expm(M);   Ad = E(1:2,1:2);    Bd = E(1:2,3:5);
    n = numel(q);  y = zeros(n,1);  x = [T0; T0];
    for k = 1:n
        y(k) = x(1);
        x = Ad*x + Bd*[q(k); Ta(k); Qint(k)];
    end
end

function J = jacobian(res, p, r0)
% Ileri farkla Jacobian: J(:,i) = (r(p + h e_i) - r(p)) / h
    h = 1e-6;  J = zeros(numel(r0), numel(p));
    for i = 1:numel(p)
        dp = zeros(size(p));  dp(i) = h;
        J(:,i) = (res(p + dp) - r0) / h;
    end
end
