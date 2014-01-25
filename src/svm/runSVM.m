%% init
clear all; close all; clc
globals();
featureDL_folder = '../feature-deeplearning';
[annotations_train, annotations_val, annotations_test] = loadAnnotations();
load(fullfile(devkit_folder, 'classes.mat')); % load classes

%% Load Data
Xtrain = []; Xval = []; Xtest = [];
ytrain = []; yval = [];

%  load train
fprintf('loading Xtrain...');
for i=1:40,
    filename = sprintf('%s/train_%d.mat', featureDL_folder, i);
    load(filename);
    Xtrain = [Xtrain; scores];
end
fprintf('done\n');
fprintf('loading ytrain...');
for i=1:size(annotations_train,1)
     clss = annotations_train{i}.annotation.classes;
     ytmp = [];
     for j=1:size(classes,2)
        ytmp(1,end+1) = str2double(clss.(classes{j}));
     end
     ytrain(end+1,:) = ytmp;
end
fprintf('done\n');

%  load validation
fprintf('loading Xval...');
for i=1:10,
    filename = sprintf('%s/val_%d.mat', featureDL_folder, i);
    load(filename);
    Xval = [Xval; scores];
end
fprintf('done\n');
fprintf('loading yval...');
for i=1:size(annotations_val,1)
     clss = annotations_val{i}.annotation.classes;
     ytmp = [];
     for j=1:size(classes,2)
        ytmp(1,end+1) = str2double(clss.(classes{j}));
     end
     yval(end+1,:) = ytmp;
end
fprintf('done\n');

%  load test
fprintf('loading Xtest...');
for i=1:25,
    filename = sprintf('%s/test_%d.mat', featureDL_folder, i);
    load(filename);
    Xtest = [Xtest; scores];
end
fprintf('done\n');

%% DEBUG : shrink the image size
if(flag_debug)
    Xtrain = Xtrain(1:debug_num_imgs, :);
    ytrain = ytrain(1:debug_num_imgs, :);
    Xval   = Xval(1:debug_num_imgs, :);
    yval   = yval(1:debug_num_imgs, :);
    Xtest  = Xtest(1:debug_num_imgs, :);
end

%% Normalize
% train
min_val = min(Xtrain);
max_val = max(Xtrain);
Xtrain = Xtrain - repmat(min_val, [size(Xtrain,1) 1]);
Xtrain = Xtrain ./ repmat((max_val - min_val), [size(Xtrain,1) 1]);

% val
Xval = Xval - repmat(min_val, [size(Xval,1) 1]);
Xval = Xval ./ repmat((max_val - min_val), [size(Xval,1) 1]);

% test
Xtest = Xtest - repmat(min_val, [size(Xtest,1) 1]);
Xtest = Xtest ./ repmat((max_val - min_val), [size(Xtest,1) 1]);


%% Train SVM
%svm_c_cand = [0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15];
svm_c_cand = 0.05:0.001:0.2;

result_AP = zeros(length(classes), length(svm_c_cand));

for iii = 1:length(svm_c_cand)
    svm_c = svm_c_cand(iii);
    fprintf('----- svm_c = %d -----\n', svm_c);
    % train
    for i = 1:length(classes)
        %svm_c = 1;
        opt = sprintf('-s 2 -B 1 -c %f -q', svm_c);
        model{i} = train(ytrain(:,i), sparse(double(Xtrain)), opt);
        %model{i} = svmtrain(ytrain(:,i), sparse(double(Xtrain)), '-s 0 -t 2 -q');
        
        % Reverse weights
        if model{i}.Label(1) == 0
            model{i}.w = -model{i}.w;
            model{i}.Label = [1;0];
        end
    end
    
    if 0
        % compute AP
        accuracies = zeros(size(classes,2),1);
        for i = 1:length(classes)
            [~, ~, prob] = predict(ytrain(:,i), sparse(double(Xtrain)), model{i}, '-q');
            %[~, ~, prob] = svmpredict(ytrain(:,i), sparse(double(Xtrain)), model{i}, '-q');
            AP = computeAP(prob, ytrain(:,i), 1)*100;
            accuracies(i, 1) = AP;
            fprintf('Train Accuracy (%13s) : %0.3f%%\n', classes{i}, AP);
        end;
        fprintf('Train Accuracy Average : %0.3f%%\n', mean(accuracies));
    end
    
    
    %% Validate
    % compute AP
    accuracies = zeros(size(classes,2),1);
    for i = 1:length(classes)
        [~, ~, prob] = predict(yval(:,i), sparse(double(Xval)), model{i}, '-q');
        %[~, ~, prob] = svmpredict(yval(:,i), sparse(double(Xval)), model{i}, '-q');
        AP = computeAP(prob, yval(:,i), 1)*100;
        accuracies(i, 1) = AP;
        fprintf('Val Accuracy (%13s) : %0.3f%%\n', classes{i}, AP);
        result_AP(i,iii) = AP;
    end;
    fprintf('Val Accuracy Average : %0.3f%%\n', mean(accuracies));
    
end

%% Show the best svm_c
[v,I] = max(result_AP,[],2);
for i = 1:length(classes)
    fprintf('Best SVM_C (%13s) : %.3f (%.3f%%)\n', classes{i}, svm_c_cand(I(i)), v(i));
end
fprintf('Val Accuracy Average : %0.3f%%\n', mean(v));

if 0
    %% Predict Test-set
    % predict
    probs = [];
    for i =1:length(classes)
        [~, ~, prob] = predict(zeros(size(Xtest,1),1), sparse(double(Xtest)), model{i}, '-q');
        %[~, ~, prob] = svmpredict(zeros(size(Xtest,1),1), sparse(double(Xtest)), model{i}, '-q');
        probs(end+1,:) = prob;
    end
    serialize(probs', 'test');
end