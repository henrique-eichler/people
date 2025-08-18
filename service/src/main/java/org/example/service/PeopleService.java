package org.example.service;

import org.example.model.People;
import org.example.repository.PeopleRepository;

import java.util.List;
import java.util.Optional;

/**
 * Service layer for People operations.
 */
public class PeopleService {
    private final PeopleRepository repository;

    public PeopleService() {
        this(new PeopleRepository());
    }

    public PeopleService(PeopleRepository repository) {
        this.repository = repository;
    }

    public People create(String name, int age) {
        People p = new People(null, name, age);
        return repository.save(p);
    }

    public Optional<People> getById(Long id) {
        return repository.findById(id);
    }

    public List<People> getAll() {
        return repository.findAll();
    }

    public Optional<People> update(Long id, String name, int age) {
        People p = new People(id, name, age);
        return repository.update(id, p);
    }

    public boolean delete(Long id) {
        return repository.deleteById(id);
    }

    public long count() {
        return repository.count();
    }
}
